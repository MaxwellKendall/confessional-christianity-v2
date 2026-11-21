// Search-intent meta titles and descriptions for library entry pages (TKL-681):
// "Westminster Shorter Catechism Question 1 — What Is the Chief End of Man?".
// Every part is derived from the stored entry, its parent and its document, so
// each of the ~1,000 entry pages gets its own title and description.
import { stripFootnoteMarkers, truncateForMeta } from './helpers';
import type { ConfessionEntry, ContentById } from './domain';

const QUESTION = /^Question\s(\d+):\s*(.*)$/;
const CHAPTER = /^Chapter\s(\d+):\s*(.*)$/;
const NUMBERED_CHILD = /^(Article|Rejection)\s(\d+)$/;

// Minor words stay lower case unless they open the title (Chicago-style).
const MINOR_WORDS = new Set([
  'a', 'an', 'the', 'and', 'but', 'or', 'nor', 'for', 'so', 'yet',
  'of', 'in', 'on', 'to', 'by', 'at', 'as', 'from', 'into', 'unto', 'with', 'upon',
]);

export const titleCase = (text: string): string => text
  .split(' ')
  .map((word, i) => {
    if (!word) return word;
    const lower = word.toLowerCase();
    if (i > 0 && MINOR_WORDS.has(lower)) return lower;
    if (word !== lower && word === word.toUpperCase()) return word; // LORD, acronyms
    return word.charAt(0).toUpperCase() + word.slice(1);
  })
  .join(' ');

const subjectOf = (chapterTitle: string): string => chapterTitle.replace(CHAPTER, '$2').replace(/\.$/, '').trim();

// The chapter that holds an article/rejection: "CoD-1-rejections" → "CoD-1".
const parentChapter = (entry: ConfessionEntry, contentById: ContentById): ConfessionEntry | undefined => (
  contentById[entry.parent.replace(/-(articles|rejections)$/, '')]
);

interface Location {
  // "Question 1", "Chapter 1, Article 2", "Chapter 3", "Thesis 1"
  label: string;
  // short citation for descriptions: "Q. 1", "1.2", "Chapter 3", "Thesis 1"
  cite: string;
  subject?: string;
}

const locate = (entry: ConfessionEntry, contentById: ContentById): Location => {
  const title = stripFootnoteMarkers(entry.title ?? entry.id).replace(/\s+/g, ' ').trim();
  const question = title.match(QUESTION);
  if (question) {
    return { label: `Question ${question[1]}`, cite: `Q. ${question[1]}`, subject: question[2] };
  }
  const chapter = title.match(CHAPTER);
  if (chapter) {
    return { label: `Chapter ${chapter[1]}`, cite: `Chapter ${chapter[1]}`, subject: subjectOf(title) };
  }
  const child = title.match(NUMBERED_CHILD);
  const parent = parentChapter(entry, contentById);
  const parentMatch = parent?.title?.match(CHAPTER);
  if (child && parentMatch) {
    const [, kind, n] = child;
    const cite = kind === 'Article' ? `${parentMatch[1]}.${n}` : `${parentMatch[1]}, ${kind} ${n}`;
    return { label: `Chapter ${parentMatch[1]}, ${kind} ${n}`, cite, subject: subjectOf(parent!.title) };
  }
  return { label: title, cite: title };
};

export const entryMetaTitle = (
  documentTitle: string,
  entry: ConfessionEntry,
  contentById: ContentById,
): string => {
  const { label, subject } = locate(entry, contentById);
  return subject
    ? `${documentTitle} ${label} — ${titleCase(subject)}`
    : `${documentTitle} — ${label}`;
};

export const entryMetaDescription = (
  documentTitle: string,
  entry: ConfessionEntry,
  contentById: ContentById,
): string => {
  const { cite } = locate(entry, contentById);
  const text = stripFootnoteMarkers(entry.text ?? '').replace(/\s+/g, ' ').trim();
  const isQuestion = QUESTION.test(entry.title ?? '');
  return truncateForMeta(`${documentTitle} ${cite}${isQuestion ? ' answer' : ''}: ${text}`);
};
