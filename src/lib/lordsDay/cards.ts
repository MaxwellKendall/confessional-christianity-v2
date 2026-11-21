import { BIBLE_BOOKS, citationToOsis, parseOsisBibleReference } from '@/lib/bible';

// The Lord's Day loop turns sermon notes into exactly three kinds of card
// (spec: "the Lord's Day loop", D3). Anything else the model returns is
// rejected here, never passed through to the app.
export const CARD_KINDS = ['key_point', 'quote', 'verse'] as const;
export type CardKind = (typeof CARD_KINDS)[number];

export interface DraftCard {
  /** `p<page>-<order>`: stable within one response */
  id: string;
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
    | 'bad_reference';
}

export const MAX_TEXT_LENGTH: Record<'key_point' | 'quote', number> = { key_point: 280, quote: 400 };
export const MAX_CARDS_PER_PAGE = 12;
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
  },
  required: ['extractedText', 'cards'],
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
    if (cards.length >= MAX_CARDS_PER_PAGE) return;
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
