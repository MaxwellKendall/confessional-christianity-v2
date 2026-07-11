// Presentation helpers for confession entries: the mockups render entry
// titles in short forms ("Q. 1 — What is the chief end of man?", "Chapter 1 ·
// Article 2") derived from the stored titles documented in docs/DOMAIN.md.
import { parseOsisBibleReference } from './bible';
import { stripFootnoteMarkers } from './helpers';
import type { ConfessionEntry, ContentById } from './domain';

const QUESTION_PREFIX = /^Question\s(\d+):\s*/;

// TOC / list row title: "Q. 1 — What is the chief end of man?" for Q&A
// entries; stored titles ("Article 1", "Chapter 3: Of ...") pass through.
export const tocRowTitle = (entry: ConfessionEntry): string => {
  const match = entry.title?.match(QUESTION_PREFIX);
  if (match) {
    return `Q. ${match[1]} — ${entry.title.replace(QUESTION_PREFIX, '')}`;
  }
  return entry.title ?? entry.id;
};

// Small-caps label above the entry text: "Q. 2", "Chapter 1 · Article 2",
// "Chapter 3", "Thesis 12", "Rejection 2".
export const entryPageLabel = (entry: ConfessionEntry, contentById?: ContentById): string => {
  const match = entry.title?.match(QUESTION_PREFIX);
  if (match) return `Q. ${match[1]}`;
  const head = entry.title?.split(':')[0] ?? entry.id;
  const parent = contentById?.[entry.parent.replace(/-(articles|rejections)$/, '')];
  if (parent?.title && /^(Article|Rejection)\s\d+$/.test(head)) {
    const parentHead = parent.title.split(':')[0];
    return `${parentHead} · ${head}`;
  }
  return head;
};

// The entry's reading text. Q&A entries render as question + answer lines;
// footnote markers are stripped for display (proof texts render separately).
export const entryQuoteLines = (entry: ConfessionEntry): string[] => {
  const clean = stripFootnoteMarkers(entry.text ?? '');
  const match = entry.title?.match(QUESTION_PREFIX);
  if (match) {
    const question = entry.title.replace(QUESTION_PREFIX, '');
    return [`Q. ${question}`, `A. ${clean}`];
  }
  return [clean];
};

// A run of entry text ending at a footnote marker; the marker's proof texts
// support exactly this clause, per the source documents' own footnoting.
export interface TextSegment {
  text: string;
  marker?: string;
}

// Splits stored text ("...being buried,[1] and continuing...") into clause
// segments keyed by the marker that closes each one; the tail after the last
// marker comes through markerless.
export const entryTextSegments = (text = ''): TextSegment[] => {
  const parts = text.split(/\[([a-zA-Z0-9]+)\]/g);
  const segments: TextSegment[] = [];
  for (let i = 0; i < parts.length; i += 2) {
    const segmentText = parts[i].replace(/\s+/g, ' ');
    const marker = parts[i + 1];
    if (!segmentText && !marker) continue;
    segments.push(marker ? { text: segmentText, marker } : { text: segmentText });
  }
  return segments;
};

// The clause a given footnote marker annotates, for quoting on the scripture
// canonical page. Leading punctuation belongs to the previous clause (the
// prior marker sits before the comma), so it is shed along with whitespace.
export const clauseForMarker = (entry: ConfessionEntry, marker: string): string => (entryTextSegments(entry.text ?? '')
  .find((segment) => segment.marker === marker)?.text ?? '')
  .replace(/^[\s,;:.]+/, '')
  .trim();

// entryQuoteLines with the footnote markers kept in place, as lines of
// segments — the entry page renders the markers as superscripts anchoring
// each clause to its proof texts.
export const entryQuoteSegments = (entry: ConfessionEntry): TextSegment[][] => {
  const answer = entryTextSegments(entry.text ?? '');
  const match = entry.title?.match(QUESTION_PREFIX);
  if (match) {
    const question = entry.title.replace(QUESTION_PREFIX, '');
    return [[{ text: `Q. ${question}` }], [{ text: 'A. ' }, ...answer]];
  }
  return [answer];
};

export interface ProofTextRef {
  osis: string;
  citation: string;
}

export interface ProofTextGroup {
  marker: string;
  refs: ProofTextRef[];
}

// Proof texts grouped by footnote marker, in the order the markers appear in
// the text (falling back to the stored key order for any marker that never
// appears — a data quirk, not the norm).
export const proofTextGroups = (entry: ConfessionEntry): ProofTextGroup[] => {
  if (!entry.verses) return [];
  const stored = Object.keys(entry.verses);
  const inTextOrder = entryTextSegments(entry.text ?? '')
    .map((segment) => segment.marker)
    .filter((marker): marker is string => Boolean(marker && stored.includes(marker)));
  const markers = Array.from(new Set([...inTextOrder, ...stored]));
  return markers.map((marker) => ({
    marker,
    refs: entry.verses![marker].map((osis) => ({
      osis,
      citation: parseOsisBibleReference(osis),
    })),
  }));
};
