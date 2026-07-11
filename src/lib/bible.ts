// OSIS bible-reference helpers, ported from v1 scripts/helpers + scripts/dataMapping.
// The normalized-data proof texts store citations as OSIS refs ("1Cor.10.31",
// "Ps.73.25-Ps.73.28"); these convert them to and from human-readable form.

export const bibleBookByAbbreviation: Record<string, string> = {
  Gen: 'Genesis',
  Exod: 'Exodus',
  Lev: 'Leviticus',
  Num: 'Numbers',
  Deut: 'Deuteronomy',
  Josh: 'Joshua',
  Judg: 'Judges',
  Ruth: 'Ruth',
  '1Sam': '1 Samuel',
  '2Sam': '2 Samuel',
  '1Kgs': '1 Kings',
  '2Kgs': '2 Kings',
  '1Chr': '1 Chronicles',
  '2Chr': '2 Chronicles',
  Ezra: 'Ezra',
  Neh: 'Nehemiah',
  Esth: 'Esther',
  Job: 'Job',
  Ps: 'Psalms',
  Prov: 'Proverbs',
  Eccl: 'Ecclesiastes',
  Song: 'Song of Solomon',
  Isa: 'Isaiah',
  Jer: 'Jeremiah',
  Lam: 'Lamentations',
  Ezek: 'Ezekiel',
  Dan: 'Daniel',
  Hos: 'Hosea',
  Joel: 'Joel',
  Amos: 'Amos',
  Obad: 'Obadiah',
  Jonah: 'Jonah',
  Mic: 'Micah',
  Nah: 'Nahum',
  Hab: 'Habakkuk',
  Zeph: 'Zephaniah',
  Hag: 'Haggai',
  Zech: 'Zechariah',
  Mal: 'Malachi',
  New: 'Testament',
  Matt: 'Matthew',
  Mark: 'Mark',
  Luke: 'Luke',
  John: 'John',
  Acts: 'Acts',
  Rom: 'Romans',
  '1Cor': '1 Corinthians',
  '2Cor': '2 Corinthians',
  Gal: 'Galatians',
  Eph: 'Ephesians',
  Phil: 'Philippians',
  Col: 'Colossians',
  '1Thess': '1 Thessalonians',
  '2Thess': '2 Thessalonians',
  '1Tim': '1 Timothy',
  '2Tim': '2 Timothy',
  Titus: 'Titus',
  Phlm: 'Philemon',
  Heb: 'Hebrews',
  Jas: 'James',
  '1Pet': '1 Peter',
  '2Pet': '2 Peter',
  '1John': '1 John',
  '2John': '2 John',
  '3John': '3 John',
  Jude: 'Jude',
  Rev: 'Revelation',
};

// Renders an OSIS reference ("Ps.73.25-Ps.73.28") as a human-readable
// citation ("Psalms 73:25-28"), collapsing ranges within a book/chapter.
export const parseOsisBibleReference = (osisStr: string): string => {
  if (!osisStr) return '';
  if (osisStr.includes(',')) {
    return osisStr
      .split(',')
      .map((s) => parseOsisBibleReference(s))
      .join(',');
  }
  const splitStr = osisStr.split('-');
  return splitStr.reduce((acc, str, i, srcArr) => {
    const bookChapterVerse = str.split('.');
    const book = bibleBookByAbbreviation[bookChapterVerse[0]];
    const chapterVerse = bookChapterVerse.slice(1).join(':');
    if (i === 0) {
      return `${book} ${chapterVerse}`;
    }
    const [prevBook, prevChapter] = srcArr[i - 1].split('.');
    if (prevBook === bookChapterVerse[0] && prevChapter === bookChapterVerse[1]) {
      return `${acc}-${bookChapterVerse[2]}`;
    }
    if (prevBook === bookChapterVerse[0]) {
      return `${acc}-${chapterVerse}`;
    }
    return `${acc} - ${book} ${chapterVerse}`;
  }, '');
};

const toOsisMap: Record<string, string> = Object.entries(bibleBookByAbbreviation).reduce(
  (obj, [key, value]) => ({
    ...obj,
    [value.toLowerCase()]: key,
  }),
  { psalm: 'Ps' },
);

export const toOsis = (str: string): string => toOsisMap[str.toLowerCase()];

// Books the ESV cites without a chapter number ("Jude 4" means Jude 1:4).
const SINGLE_CHAPTER_BOOKS = new Set(['Obad', 'Phlm', '2John', '3John', 'Jude']);

// Inverse of parseOsisBibleReference for human citations as the ESV API (and
// therefore the Algolia citations index) canonicalizes them: "Acts 2:24–27",
// "Psalm 16:10", "1 Corinthians 15:3–4", "Acts 1:1–2:4", chapter-level refs
// like "Psalm 73" and "Hebrews 8–10". Returns null when the string doesn't
// fit that shape, so callers can degrade gracefully.
export const citationToOsis = (citation: string): string | null => {
  const normalized = citation.replace(/[–—]/g, '-').trim();
  const match = normalized.match(/^([1-3]?\s?[A-Za-z ]+?)\s+(\d+)(?::(\d+))?(?:\s*-\s*(?:(\d+):)?(\d+))?$/);
  if (!match) return null;
  const [, bookName, first, second, endChapter, end] = match;
  const book = toOsis(bookName);
  if (!book) return null;
  // in single-chapter books the leading number is already the verse
  const [chapter, verse] = SINGLE_CHAPTER_BOOKS.has(book) && !second
    ? ['1', first]
    : [first, second];
  const start = verse ? `${book}.${chapter}.${verse}` : `${book}.${chapter}`;
  if (!end) return start;
  // a chapter-only start makes the range end a chapter too ("Hebrews 8–10"),
  // unless the end carries its own chapter:verse
  if (!verse && !endChapter) return `${start}-${book}.${end}`;
  return `${start}-${book}.${endChapter ?? chapter}.${end}`;
};
