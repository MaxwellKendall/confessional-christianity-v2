// Sharing a confession or catechism. A share is an entry plus what was
// picked out of it: the whole entry, one clause (named by the footnote
// marker that closes it, so it carries exactly that clause's proof texts),
// or a selected run of text. Everything a share needs travels in its URL:
// `/share/<document>/<entry>`, plus `?c=<marker>` or `?r=<start>-<end>`. That
// keeps share links stable, previewable, and free of any stored state.
//
// Client-safe: works on a single ConfessionEntry, never the content map.
import { parseOsisBibleReference } from './bible';
import type { ConfessionEntry } from './domain';
import { entryTextSegments, type ProofTextRef } from './entryDisplay';

export type ShareSelection =
  | { kind: 'entry' }
  | { kind: 'clause'; marker: string }
  /** Character offsets into the entry's reading text (see readingText). */
  | { kind: 'range'; start: number; end: number };

/** The longest selection a share keeps; past this an image stops reading
 * as a quote. Longer selections are cut at a word boundary with an ellipsis. */
export const MAX_QUOTE_CHARS = 420;

const QUESTION_PREFIX = /^Question\s(\d+):\s*/;

export interface ClauseSpan {
  start: number;
  end: number;
  text: string;
  marker?: string;
}

/** The entry text with footnote markers removed, exactly as the reader
 * shows it (segment by segment). Selection offsets index into this. */
export const readingText = (entry: ConfessionEntry): string => entryTextSegments(entry.text ?? '')
  .map((s) => s.text)
  .join('');

/** Each clause's position in readingText, keyed by the marker closing it. */
export const clauseSpans = (entry: ConfessionEntry): ClauseSpan[] => {
  let offset = 0;
  return entryTextSegments(entry.text ?? '').map((segment) => {
    const span: ClauseSpan = { start: offset, end: offset + segment.text.length, text: segment.text };
    if (segment.marker) span.marker = segment.marker;
    offset = span.end;
    return span;
  });
};

// ---------------------------------------------------------------------------
// URL encoding

export const selectionQuery = (selection: ShareSelection): string => {
  switch (selection.kind) {
    case 'clause': return `c=${encodeURIComponent(selection.marker)}`;
    case 'range': return `r=${selection.start}-${selection.end}`;
    default: return '';
  }
};

type Params = URLSearchParams | Record<string, string | string[] | undefined>;

const param = (params: Params, key: string): string | undefined => {
  const value = params instanceof URLSearchParams ? params.get(key) ?? undefined : params[key];
  return Array.isArray(value) ? value[0] : value;
};

/** Reads a selection back out of share-URL params. Malformed values fall
 * back to the whole entry rather than failing: a mangled link still opens. */
export const parseSelection = (params: Params): ShareSelection => {
  const marker = param(params, 'c');
  if (marker && /^[A-Za-z0-9]{1,4}$/.test(marker)) return { kind: 'clause', marker };
  const range = param(params, 'r')?.match(/^(\d{1,5})-(\d{1,5})$/);
  if (range) {
    const [start, end] = [Number(range[1]), Number(range[2])];
    if (end > start) return { kind: 'range', start, end };
  }
  return { kind: 'entry' };
};

/** `/share/<document slug>/<entry segment>[?…]` — relative, for links. */
export const sharePath = (slug: string, segment: string, selection: ShareSelection): string => {
  const query = selectionQuery(selection);
  return `/share/${slug}/${segment}${query ? `?${query}` : ''}`;
};

/** The share URL's image, in one of the two shapes the image route draws:
 * `og` (1200×630, link previews) or `portrait` (1080×1350, posting). */
export const shareImagePath = (path: string, format: 'og' | 'portrait'): string => {
  const [base, query] = path.split('?');
  const params = new URLSearchParams(query);
  params.set('f', format);
  return `${base}/image?${params}`;
};

/** Where "read in context" goes: the library entry, with the clause (or
 * selection) highlighted by the reader on arrival. */
export const contextPath = (slug: string, segment: string, selection: ShareSelection): string => {
  const base = `/library/${slug}/${segment}`;
  if (selection.kind === 'clause') return `${base}#c-${selection.marker}`;
  if (selection.kind === 'range') return `${base}#r-${selection.start}-${selection.end}`;
  return base;
};

// ---------------------------------------------------------------------------
// the quote itself

export interface ShareQuote {
  /** The catechism question, for Q&A entries (always shown with the answer). */
  question: string | null;
  /** The quoted words, with ellipses where they cut into a sentence. */
  quote: string;
  /** What was quoted: the whole entry, a clause, or a selection. */
  selection: ShareSelection;
  /** The proof texts behind the quoted words, in text order, deduplicated. */
  refs: ProofTextRef[];
}

/** Trims a selection to whole words; a range landing mid-word is widened
 * to the word it touches, so a sloppy touch selection still reads cleanly. */
const snapToWords = (text: string, start: number, end: number): [number, number] => {
  let s = Math.max(0, Math.min(start, text.length));
  let e = Math.max(s, Math.min(end, text.length));
  while (s > 0 && /\w/.test(text[s - 1]) && /\w/.test(text[s])) s -= 1;
  while (e < text.length && /\w/.test(text[e - 1] ?? '') && /\w/.test(text[e])) e += 1;
  while (s < e && /\s/.test(text[s])) s += 1;
  while (e > s && /\s/.test(text[e - 1])) e -= 1;
  return [s, e];
};

const capLength = (quote: string): { text: string; cut: boolean } => {
  if (quote.length <= MAX_QUOTE_CHARS) return { text: quote, cut: false };
  const head = quote.slice(0, MAX_QUOTE_CHARS);
  const lastSpace = head.lastIndexOf(' ');
  return { text: head.slice(0, lastSpace > 0 ? lastSpace : MAX_QUOTE_CHARS).replace(/[\s,;:]+$/, ''), cut: true };
};

const refsFor = (entry: ConfessionEntry, markers: string[]): ProofTextRef[] => {
  const seen = new Set<string>();
  const refs: ProofTextRef[] = [];
  for (const marker of markers) {
    for (const osis of entry.verses?.[marker] ?? []) {
      if (seen.has(osis)) continue;
      seen.add(osis);
      refs.push({ osis, citation: parseOsisBibleReference(osis) });
    }
  }
  return refs;
};

/** What a share of `entry` shows. Returns null when the selection names
 * nothing in the entry (an unknown marker, an empty range). */
export const buildShareQuote = (entry: ConfessionEntry, selection: ShareSelection): ShareQuote | null => {
  const match = entry.title?.match(QUESTION_PREFIX);
  const question = match ? entry.title.replace(QUESTION_PREFIX, '') : null;
  const text = readingText(entry);
  const spans = clauseSpans(entry);

  let start = 0;
  let end = text.length;
  let markers: string[];
  let canonical = selection;
  if (selection.kind === 'clause') {
    const span = spans.find((s) => s.marker === selection.marker);
    if (!span) return null;
    [start, end] = [span.start, span.end];
    markers = [selection.marker];
  } else if (selection.kind === 'range') {
    [start, end] = snapToWords(text, selection.start, selection.end);
    if (end - start < 2) return null;
    // the snapped range is the one the URL carries, so one quote, one link
    canonical = { kind: 'range', start, end };
    // a clause's proof texts stand behind any of its words being quoted
    markers = spans.filter((s) => s.marker && s.start < end && s.end > start).map((s) => s.marker!);
  } else {
    markers = spans.flatMap((s) => (s.marker ? [s.marker] : []));
  }

  // a clause or selection that starts mid-sentence leads with an ellipsis;
  // leading punctuation belongs to the clause before (see clauseForMarker)
  let body = text.slice(start, end).replace(/^[\s,;:.]+/, '').trim();
  if (selection.kind !== 'entry' && /[,;:]$/.test(body)) body = body.slice(0, -1);
  const { text: capped, cut } = capLength(body);
  const opensMidSentence = start > 0 && !/[.?!]\s*$/.test(text.slice(0, start).trimEnd() || '.');
  const closesMidSentence = cut || (end < text.length && !/[.?!]$/.test(capped));
  const quote = `${opensMidSentence ? '…' : ''}${capped}${closesMidSentence ? '…' : ''}`;

  return { question, quote, selection: canonical, refs: refsFor(entry, markers) };
};

/** Plain text for "Copy text" and the share sheet's text field. */
export const shareText = (
  quote: ShareQuote,
  { source, url, scripture }: { source: string; url?: string; scripture?: { citation: string; text: string } | null },
): string => {
  const lines = [
    quote.question ? `Q. ${quote.question}` : null,
    quote.question ? `A. ${quote.quote}` : `“${quote.quote}”`,
    `— ${source}`,
  ];
  if (scripture) lines.push('', `“${scripture.text}” (${scripture.citation}, ESV)`);
  else if (quote.refs.length) lines.push('', `Scripture: ${quote.refs.map((r) => r.citation).join('; ')}`);
  if (url) lines.push('', url);
  return lines.filter((l): l is string => l !== null).join('\n');
};
