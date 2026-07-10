import { bibleBookByAbbreviation, bibleApiAbbrByOsis } from '../dataMapping/index.js';

export const parseOsisBibleReference = (osisStr) => {
  if (!osisStr) return '';
  if (osisStr.includes(',')) {
    return osisStr
      .split(',')
      .map((s) => parseOsisBibleReference(s))
      .join(',');
  }
  const splitStr = osisStr.split('-');
  return splitStr
    .reduce((acc, str, i, srcArr) => {
      // This scares me, assuming that bookChapterVerse always has 3 items.
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

const toOsisMap = Object.entries(bibleBookByAbbreviation).reduce((obj, [key, value]) => ({
  ...obj,
  [value.toLowerCase()]: key,
}), { psalm: 'Ps' });

export const toOsis = (str) => toOsisMap[str.toLowerCase()];

export const mapOSisTextToApiValues = (osisStr) => {
  if (!osisStr) return '';
  const splitStr = osisStr.split('-');
  return splitStr
    .reduce((acc, str, i) => {
      const bookChapterVerse = str.split('.');
      const book = bibleApiAbbrByOsis[bookChapterVerse[0]];
      const chapterVerse = bookChapterVerse.slice(1).join('.');
      if (i !== 0) {
        return `${acc}-${book}.${chapterVerse}`;
      }
      return `${book}.${chapterVerse}`;
    }, '');
};

export const addRecordToIndex = async (index, record) => index
  .saveObject({ ...record, objectID: record.id })
  .then(() => {
    console.log('record added: ', record.id);
    return Promise.resolve();
  })
  .catch((e) => {
    console.error('Error adding record to index', e);
  });

export const getConfessionalAbbreviationId = (name) => name.split(' ').reduce((acc, str) => `${acc}${str[0]}`, '');
