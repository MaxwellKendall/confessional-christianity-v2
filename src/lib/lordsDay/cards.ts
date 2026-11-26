import { BIBLE_BOOKS, citationToOsis, parseOsisBibleReference } from '@/lib/bible';

// The Lord's Day loop turns sermon notes into exactly three kinds of card
// (spec: "the Lord's Day loop", D3). Anything else the model returns is
// rejected here, never passed through to the app.
export const CARD_KINDS = ['key_point', 'quote', 'verse'] as const;
export type CardKind = (typeof CARD_KINDS)[number];

export interface DraftCard {
  /** `p<page>-<order>`: stable within one response */
  id: string;
  /** stable identity of this generated card across retries (independent of request page index and user edits) */
  sourceKey?: string;
  kind: CardKind;
  /** index of the photo (0 for typed notes) */
  page: number;
  /** position within its page; the full list is ordered by (page, order) */
  order: number;
  /** key_point and quote only */
  text?: string;
  /** verse only: a canonical human reference ("Psalms 86:5"), never Scripture text */
  reference?: string;
  /** verse only: the OSIS id the app's reader fetches the text by */
  osis?: string;
  /** quote only: the preacher named in the request; absent when the request names none */
  attribution?: string;
}

export interface Rejection {
  index: number;
  reason:
    | 'not_object'
    | 'unknown_kind'
    | 'empty_text'
    | 'text_too_long'
    | 'quote_too_short'
    | 'quote_not_in_source'
    | 'bad_reference'
    /** past MAX_CARDS_PER_PAGE: kept out to bound cost, but still counted */
    | 'over_limit';
}

export const MAX_TEXT_LENGTH: Record<'key_point' | 'quote', number> = { key_point: 280, quote: 400 };
// A bound on cost and payload only. A dense page of notes can carry well over a
// dozen points, so this sits far above what a real page yields; the number of
// cards is decided by the notes (see INSTRUCTIONS in gemini.ts), not by this.
export const MAX_CARDS_PER_PAGE = 24;
const MIN_QUOTE_WORDS = 3;

// Sent to Gemini as `responseJsonSchema`, so "exactly three kinds" is a property
// of the request. validateGeneratedCards re-checks everything regardless: a
// GEMINI_CARDS_MODEL override may not honour the schema.
export const GENERATION_SCHEMA = {
  type: 'object',
  properties: {
    extractedText: {
      type: 'string',
      description: 'A faithful transcription of the handwritten notes, line by line, without corrections.',
    },
    cards: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          kind: { type: 'string', enum: [...CARD_KINDS] },
          text: { type: 'string', description: 'key_point: one sentence. quote: words copied exactly from extractedText.' },
          reference: { type: 'string', description: 'verse only: a Bible reference like "Psalm 86:5", never verse text.' },
        },
        required: ['kind'],
      },
    },
    // TKL-1061. Optional and additive: TKL-1058 extends the same object later.
    sermon: {
      type: 'object',
      description: 'Which sermon these notes are on, only as the notes themselves state it. Omit any field the notes do not say.',
      properties: {
        title: { type: 'string', description: "The sermon's title as written in the notes." },
        preacher: { type: 'string', description: 'The preacher as written in the notes.' },
        passage: { type: 'string', description: 'The sermon\'s main text as a Bible reference with the full book name ("Revelation 2:8-11").' },
        church: { type: 'string', description: 'The church or congregation as written in the notes.' },
        serviceDate: { type: 'string', description: 'The date written on the notes, as YYYY-MM-DD.' },
      },
    },
  },
  required: ['extractedText', 'cards'],
};

// MARK: Which sermon (TKL-1061)

export const SERMON_FIELDS = ['title', 'preacher', 'passage', 'church', 'serviceDate'] as const;
export type SermonField = (typeof SERMON_FIELDS)[number];
/** Each field is null unless the notes say it. */
export type SermonDetails = Record<SermonField, string | null>;

export const emptySermon = (): SermonDetails => ({ title: null, preacher: null, passage: null, church: null, serviceDate: null });
export const hasSermonDetails = (sermon: SermonDetails) => SERMON_FIELDS.some((f) => sermon[f] !== null);

const MAX_SERMON_TEXT = 120;
const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

/**
 * A title, preacher or church is kept only when the notes contain it: every word of
 * three letters or more must appear in the source. That lets the model drop an
 * article or add "Rev." but never supply a name the page doesn't have.
 */
const foundInSource = (value: string, sourceWords: Set<string>) => {
  const words = normalizeForMatch(value)
    .split(' ')
    .filter((w) => w.length >= 3 && w !== 'rev');
  return words.length > 0 && words.every((w) => sourceWords.has(w));
};

const realIsoDate = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const match = ISO_DATE.exec(value.trim());
  if (!match) return null;
  const [y, m, d] = match.slice(1).map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) return null;
  if (y < 1900 || y > 2200) return null;
  return value.trim();
};

/** The model's `sermon` object, checked against what the page actually says. */
export const validateSermon = (raw: unknown, sourceText: string): SermonDetails => {
  const sermon = emptySermon();
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return sermon;
  const fields = raw as Record<string, unknown>;
  const sourceWords = new Set(normalizeForMatch(sourceText).split(' ').filter(Boolean));
  for (const field of ['title', 'preacher', 'church'] as const) {
    const value = fields[field];
    if (typeof value !== 'string') continue;
    const trimmed = value.trim().replace(/\s+/g, ' ');
    if (!trimmed || trimmed.length > MAX_SERMON_TEXT) continue;
    if (foundInSource(trimmed, sourceWords)) sermon[field] = trimmed;
  }
  // A passage or date must have its numbers on the page: the chapter, and the day of the month.
  const numbers = new Set([...sourceWords].filter((w) => /^\d+$/.test(w)).map(Number));
  // "Matthew 5:9; 43-48" isn't one reference: keep its first part rather than nothing.
  const passage = fields.passage;
  const osis = referenceToOsis(passage) ?? (typeof passage === 'string' ? referenceToOsis(passage.split(/[;,]/)[0].trim()) : null);
  if (osis && numbers.has(Number(osis.split('.')[1]))) sermon.passage = parseOsisBibleReference(osis);
  const date = realIsoDate(fields.serviceDate);
  const year = date ? Number(date.slice(0, 4)) : 0;
  if (date && numbers.has(Number(date.slice(8, 10))) && (numbers.has(year) || numbers.has(year % 100))) sermon.serviceDate = date;
  return sermon;
};

/** One sermon for the whole request: each field's first value, in page order. */
export const mergeSermons = (pages: SermonDetails[]): SermonDetails => {
  const merged = emptySermon();
  for (const page of pages) for (const field of SERMON_FIELDS) merged[field] ??= page[field];
  return merged;
};

/** Case, quote marks, punctuation and whitespace folded away, for the quote span check. */
export const normalizeForMatch = (value: string): string =>
  value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[‘’‚‛'`]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

const stripWrappingQuotes = (value: string) => value.replace(/^["'“”‘’\s]+|["'“”‘’\s]+$/g, '');

const bookChapters = new Map(BIBLE_BOOKS.map((b) => [b.osis, b.chapters]));

const chaptersExist = (osis: string) =>
  osis.split('-').every((part) => {
    const [book, chapter] = part.split('.');
    const max = bookChapters.get(book);
    const n = Number(chapter);
    return max !== undefined && Number.isInteger(n) && n >= 1 && n <= max;
  });

/** An OSIS id for a real reference, or null. Long strings are never references. */
export const referenceToOsis = (reference: unknown): string | null => {
  if (typeof reference !== 'string' || reference.length > 40) return null;
  const osis = citationToOsis(reference.replace(/\bPss?\b\.?/i, 'Psalm'));
  return osis && chaptersExist(osis) ? osis : null;
};

export const validateGeneratedCards = (
  rawCards: unknown[],
  { sourceText, preacher, page }: { sourceText: string; preacher?: string; page: number },
): { cards: DraftCard[]; rejected: Rejection[] } => {
  const cards: DraftCard[] = [];
  const rejected: Rejection[] = [];
  const source = normalizeForMatch(sourceText);
  const attribution = preacher?.trim() || undefined;

  rawCards.forEach((raw, index) => {
    const reject = (reason: Rejection['reason']) => rejected.push({ index, reason });
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return reject('not_object');
    const { kind, text, reference } = raw as Record<string, unknown>;
    if (typeof kind !== 'string' || !(CARD_KINDS as readonly string[]).includes(kind)) return reject('unknown_kind');
    if (cards.length >= MAX_CARDS_PER_PAGE) return reject('over_limit');
    const base = { id: `p${page}-${cards.length}`, kind: kind as CardKind, page, order: cards.length };

    if (kind === 'verse') {
      const osis = referenceToOsis(reference);
      if (!osis) return reject('bad_reference');
      // only the reference leaves the server; any text the model attached is dropped
      cards.push({ ...base, reference: parseOsisBibleReference(osis), osis });
      return;
    }

    const body = typeof text === 'string' ? stripWrappingQuotes(text.trim()) : '';
    if (!body) return reject('empty_text');
    if (body.length > MAX_TEXT_LENGTH[kind as 'key_point' | 'quote']) return reject('text_too_long');

    if (kind === 'quote') {
      const normalized = normalizeForMatch(body);
      if (normalized.split(' ').filter(Boolean).length < MIN_QUOTE_WORDS) return reject('quote_too_short');
      if (!` ${source} `.includes(` ${normalized} `)) return reject('quote_not_in_source');
      cards.push({ ...base, text: body, ...(attribution ? { attribution } : {}) });
      return;
    }

    cards.push({ ...base, text: body });
  });

  return { cards, rejected };
};
