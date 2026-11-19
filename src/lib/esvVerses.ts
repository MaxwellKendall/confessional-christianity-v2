import { BIBLE_BOOKS } from '@/lib/bible';

// Splits ESV API passage text (requested with include-verse-numbers=true and
// line-length=0) into verses. The ESV marks each verse start with "[N] "; a
// chapter's first verse is "[1]" again, so a drop in N means a new chapter.
// Removing every "[N] " yields exactly the text the API returns with verse
// numbers off (checked against recorded fixtures), so anchored text matches
// the plain formatted=true response.

export interface VerseAnchor {
  osis: string;
  verse: number;
  /** UTF-16 offset into `text` where this verse starts (NSString/NSRange units) */
  offset: number;
}

export interface EsvVerse {
  osis: string;
  verse: number;
  text: string;
}

const MARKER = /\[(\d+)\] /g;

/** `start` is the ESV's BBCCCVVV id for the passage's first verse (`parsed[i][0]`). */
export const anchorPassage = (numbered: string, start: number): { text: string; anchors: VerseAnchor[] } => {
  let bookIndex = Math.floor(start / 1_000_000) - 1;
  let chapter = Math.floor(start / 1000) % 1000;
  let lastVerse = 0;
  let text = '';
  let cursor = 0;
  const anchors: VerseAnchor[] = [];
  for (const match of numbered.matchAll(MARKER)) {
    const verse = Number(match[1]);
    if (anchors.length > 0 && verse <= lastVerse) {
      chapter += 1;
      if (chapter > (BIBLE_BOOKS[bookIndex]?.chapters ?? Infinity)) {
        bookIndex += 1;
        chapter = 1;
      }
    }
    lastVerse = verse;
    text += numbered.slice(cursor, match.index);
    cursor = match.index + match[0].length;
    const book = BIBLE_BOOKS[bookIndex]?.osis ?? '';
    anchors.push({ osis: `${book}.${chapter}.${verse}`, verse, offset: text.length });
  }
  text += numbered.slice(cursor);
  return { text, anchors };
};

const chapterOf = (osis: string) => osis.split('.').slice(0, 2).join('.');

// A psalm's superscription ("A Psalm of David.") sits before its verse 1, so
// in a cross-chapter range it trails the previous chapter's last verse,
// after a blank line. Drop that trailing paragraph.
const dropSuperscription = (segment: string): string => {
  const trimmed = segment.trimEnd();
  const breaks = [...trimmed.matchAll(/\n[ \t]*\n/g)];
  const last = breaks.at(-1);
  return last ? trimmed.slice(0, last.index) : trimmed;
};

export const splitVerses = (text: string, anchors: VerseAnchor[]): EsvVerse[] =>
  anchors.map(({ osis, verse, offset }, i) => {
    const next = anchors[i + 1];
    let segment = text.slice(offset, next?.offset);
    if (next && chapterOf(next.osis) !== chapterOf(osis) && osis.startsWith('Ps.')) {
      segment = dropSuperscription(segment);
    }
    return { osis, verse, text: segment.replace(/\s+/g, ' ').trim() };
  });
