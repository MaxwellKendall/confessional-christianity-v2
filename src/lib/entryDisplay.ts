// Presentation helpers for confession entries: the mockups render entry
// titles in short forms ("Q. 1 — What is the chief end of man?", "Chapter 1 ·
// Article 2") derived from the stored titles documented in docs/DOMAIN.md.
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

// flattened, de-duplicated proof-text OSIS refs in footnote order.
export const proofTextRefs = (entry: ConfessionEntry): string[] => {
  if (!entry.verses) return [];
  return Array.from(new Set(Object.values(entry.verses).flat()));
};
