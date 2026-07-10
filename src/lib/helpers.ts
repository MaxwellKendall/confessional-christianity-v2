// Pure domain helpers, ported from v1 helpers/index.js. The parsing logic
// (parseFacets facet grammar, id parsing) is preserved verbatim; the link
// generators are updated for v2's routes: canonical entry pages live at
// /library/[confession]/[entry] (one dash-joined segment, not a catch-all)
// and search lives at /search?q=.
//
// This module stays free of the content-by-id JSON so client components can
// import the parsers without dragging ~700K of confession text into the
// bundle — the contentById-dependent title copy lives in pageTitle.ts.
import { groupBy } from 'lodash-es';

import {
  confessionCitationByIndex,
  DOCUMENTS_WITHOUT_ARTICLES,
  excludedWordsInDocumentId,
  parentIdByAbbreviation,
  slugByDocumentId,
} from './dataMapping';
import { toOsis } from './bible';
import type { ConfessionEntry, ContentById, FacetFilters } from './domain';

// returns doc id excluding of/the, so not WCoF --> WCF. This is confusing tech debt.
export const getConciseDocId = (docTitle: string): string => docTitle
  .toUpperCase()
  .split(' ')
  .filter((w) => !excludedWordsInDocumentId.includes(w))
  .reduce((acc, str) => `${acc}${str[0]}`, '');

export const getCanonicalDocId = (docTitleOrId: string): string => {
  const arr = docTitleOrId.split(' ');
  if (arr.length === 1) {
    // we have some weird ID... get the doc name & derive ID from that.
    return getConciseDocId(confessionCitationByIndex[docTitleOrId.toUpperCase()][0]);
  }
  return getConciseDocId(docTitleOrId);
};

// generates a /search?q= link for a confession id, the v2 equivalent of v1's
// query-string search route. Canons of Dort keeps its rejection/article
// disambiguation in the query grammar (CD.1.r2).
export const generateSearchLink = (confessionId: string): string => {
  const idAsArr = confessionId.split('-');
  const [id, chapterOrQuestion] = idAsArr;
  const docId = getCanonicalDocId(id);
  if (docId === 'CD') {
    // handle canons of dordt chapter
    if (idAsArr.length < 4) {
      return `/search?q=${encodeURIComponent(`${docId}.${chapterOrQuestion}`)}`;
    }
    // handle canons of dordt articles/rejections
    const query = idAsArr[2] === 'rejections'
      ? `${docId}.${chapterOrQuestion}.r${idAsArr[3]}`
      : `${docId}.${chapterOrQuestion}.${idAsArr[3]}`;
    return `/search?q=${encodeURIComponent(query)}`;
  }
  if (idAsArr.length === 2) {
    return `/search?q=${encodeURIComponent(`${docId}.${chapterOrQuestion}`)}`;
  }
  const article = idAsArr[2];
  return `/search?q=${encodeURIComponent(`${docId}.${chapterOrQuestion}.${article}`)}`;
};

// strips the leading "<documentId>-" prefix off an entry id, leaving the
// dash-joined path segment used by /library/[confession]/[entry],
// e.g. entryIdToPathSegment('CoD-1-articles-1', 'CoD') -> '1-articles-1'
export const entryIdToPathSegment = (id: string, documentId: string): string => id
  .slice(documentId.length + 1);

// resolves a confession id (e.g. "WCoF-1-2") to its canonical per-entry page
// URL, e.g. "/library/westminster-confession-of-faith/1-2". Returns null when
// no per-entry page exists for the id's document (id is malformed or belongs
// to a document without per-entry pages, e.g. CfYC).
export const generateCanonicalEntryLink = (confessionId: string): string | null => {
  const [id, ...rest] = confessionId.split('-');
  const trueDocId = parentIdByAbbreviation[getCanonicalDocId(id)];
  const slug = trueDocId && slugByDocumentId[trueDocId];
  if (!slug || rest.length === 0) return null;
  return `/library/${slug}/${rest.join('-')}`;
};

// prefers the canonical per-entry URL over the query-string search link when
// the target id is a real leaf entry with its own static page - this avoids a
// redundant client-side Algolia search just to move to the contiguous
// next/previous entry, since the canonical page needs none.
export const generateNavLink = (confessionId: string, entries: ContentById): string => {
  const target = entries[confessionId];
  if (target && !target.isParent) {
    const canonicalHref = generateCanonicalEntryLink(confessionId);
    if (canonicalHref) return canonicalHref;
  }
  return generateSearchLink(confessionId);
};

/**
 * parseConfessionId
 * @return pretty version of the ID
 * For example: fn(HC-12-45) --> Heidelberg Catechism LORD's Day 12, Question 45
 */
export const parseConfessionId = (id: string): string => {
  const fragments = id.split('-');
  return fragments.reduce((acc, frag, i, src) => {
    const isLast = src.length === i - 1;
    if (isLast) return `${acc}${confessionCitationByIndex[src[0]][i]} ${frag.toUpperCase()}`;
    if (i === 0) return `${acc}${confessionCitationByIndex[src[0]][i]} `;
    return `${acc}${confessionCitationByIndex[src[0]][i]} ${frag} `;
  }, '');
};

/**
 * getCitationContextById
 * @return a portion of an ID from which the context of the original input can be decided
 * For example, fn(HC-1-12) ==> HC or Heidelberg Catechism
 */
export const getCitationContextById = (id: string, idPositions = 1): string => id
  .split('-')
  .slice(0, idPositions)
  .join('-');

interface HasId {
  id: string;
}

/**
 * allResultsAreSameConfession
 * @return boolean indicating whether input array is all the same confession
 */
export const allResultsAreSameConfession = (results: HasId[]): boolean => {
  if (!results.length) return false;
  return Boolean(results.reduce<boolean | string>((acc, { id }, i, arr) => {
    if (i === 0) return getCitationContextById(id);
    const current = getCitationContextById(id);
    const prev = getCitationContextById(arr[i - 1].id);
    return acc && prev === current;
  }, false));
};

export const areResultsUniformChapter = (results: HasId[]): boolean => Boolean(
  results.length
  && results.reduce((acc, { id }, i, arr) => {
    if (i === 0) return true;
    const current = getCitationContextById(id, 2);
    const prev = getCitationContextById(arr[i - 1].id, 2);
    return acc && prev === current;
  }, true),
);

/**
 * getUniformConfessionTitle
 * @return the document title (Heidelberg Catechism)
 * or Chapter Title (Of Gods Eternal Decree)
 */
export const getUniformConfessionTitle = (
  [result]: { index?: string; id: string }[],
  idPosition = 1,
): string => {
  if (result.index === 'aggregate') {
    return `The ${parseConfessionId(getCitationContextById(result.id, idPosition))}`;
  }
  return '';
};

/**
 * handleSortById
 * @return number used for sorting results
 */
export const handleSortById = (
  a: { id: string; number?: number },
  b: { id: string; number?: number },
): number => {
  if (Object.keys(a).includes('number')) {
    if ((a.number as number) > (b.number as number)) return 1;
    if ((b.number as number) > (a.number as number)) return -1;
    return 0;
  }
  const [idA, idB] = [a.id.split('-'), b.id.split('-')];
  if (parseInt(idA[idA.length - 1], 10) < parseInt(idB[idB.length - 1], 10)) return -1;
  if (parseInt(idB[idB.length - 1], 10) < parseInt(idA[idA.length - 1], 10)) return 1;
  return 0;
};

const wildCardFacetRegex = /\*/;
const removeDot = (str: string | null): string | null => (str ? str.replaceAll('.', '') : str);
export const regexV2 = /(catechism\sfor\syoung\schildren|cfyc|wcf|Westminster\sConfession\sof\sFaith|hc|Heidelberg\sCatechism|WSC|Westminster\sShorter\sCatechism|WLC|Westminster\sLarger\sCatechism|39A|Thirty Nine Articles|39 Articles|tar|bcf|bc|Belgic Confession of Faith|Belgic Confession|COD|CD|Canons of Dordt|95T|95 Theses|Ninety Five Theses|ML9T|\*)|(\1\.[0-9]{1,})|(\1\2\.[0-9]{1,})|(\1\.r[0-9]{1,})|(\1\2\.r[0-9]{1,})/ig;
export const keyWords = /(westminster\sstandards|three\sforms\sof\sunity|3\sforms\sof\sunity|six\sforms\sof\sunity|6\sforms\sof\sunity)/ig;
export const bibleRegex = /(genesis|exodus|leviticus|numbers|deuteronomy|joshua|judges|ruth|1\ssamuel|2\ssamuel|1\skings|2\skings|1\schronicles|2\schronicles|ezra|nehemiah|esther|job|psalms|psalm|proverbs|ecclesiastes|song\sof\ssolomon|isaiah|jeremiah|lamentations|ezekiel|daniel|hosea|joel|amos|obadiah|jonah|micah|nahum|habakkuk|zephaniah|haggai|zechariah|malachi|testament|matthew|mark|luke|john|acts|romans|1\scorinthians|2\scorinthians|galatians|ephesians|philippians|colossians|1\sthessalonians|2\sthessalonians|1\stimothy|2\stimothy|titus|philemon|hebrews|james|1\speter|2\speter|1\sjohn|2\sjohn|3\sjohn|jude|revelation)|(\1\s[0-9]{1,}:[0-9]{1,}$|\1\s[0-9]{1,}$)|(\1\s[0-9]{1,}:[0-9]{1,}-[0-9]{1,})/ig;
export const regexTest = (regex: RegExp, value = ''): boolean => {
  regex.lastIndex = 0;
  return regex.test(value);
};

export const isEmptyKeywordSearch = (search: string): boolean => search.replace(regexV2, '') === '';

// Parses a search string into Algolia facetFilters. A nested array expresses
// OR between its filters; a bare string is an AND term (see FacetFilters type
// and docs/DOMAIN.md).
export const parseFacets = (str: string): FacetFilters => {
  const result = str.match(regexV2);
  const doc = (result && result.length && result[0]) || null;
  const chap = (result && result.length > 1 && result[1]) || null;
  const art = (result && result.length > 2 && result[2]) || null;
  if (regexTest(keyWords, str)) {
    const [keywordDoc] = str.match(keyWords) as RegExpMatchArray;
    if (keywordDoc.toLowerCase().startsWith('west')) {
      return [
        [
          `document:${confessionCitationByIndex.WSC[0]}`,
          `document:${confessionCitationByIndex.WLC[0]}`,
          `document:${confessionCitationByIndex.WCF[0]}`,
        ],
      ];
    }
    if (keywordDoc.startsWith('3') || keywordDoc.toLowerCase().startsWith('three')) {
      return [
        [
          `document:${confessionCitationByIndex.HC[0]}`,
          `document:${confessionCitationByIndex.COD[0]}`,
          `document:${confessionCitationByIndex.BC[0]}`,
        ],
      ];
    }
    if (keywordDoc.startsWith('6') || keywordDoc.toLowerCase().startsWith('six')) {
      return [
        [
          `document:${confessionCitationByIndex.HC[0]}`,
          `document:${confessionCitationByIndex.COD[0]}`,
          `document:${confessionCitationByIndex.BC[0]}`,
          `document:${confessionCitationByIndex.WSC[0]}`,
          `document:${confessionCitationByIndex.WLC[0]}`,
          `document:${confessionCitationByIndex.WCF[0]}`,
        ],
      ];
    }
  }

  if (wildCardFacetRegex.test(str)) {
    return [
      Array
        .from(new Set(Object.values(parentIdByAbbreviation)))
        .map((id) => `document:${confessionCitationByIndex[id.toUpperCase()][0]}`),
    ];
  }
  const document = doc
    ? doc
      .toUpperCase()
      .split(' ')
      .filter((w) => !excludedWordsInDocumentId.includes(w))
      .map((s, i, arr) => {
        if (arr.length === 1) return s;
        // in this case, the document is the full text vs the abbreviation.
        return s[0];
      })
      .join('')
    : null;

  const documentId = document ? getCanonicalDocId(document) : null;
  const chapter = chap && removeDot(chap);
  const article = art && removeDot(art);

  if (documentId === 'CD' && chapter && document) {
    if (article && article.toLowerCase().includes('r')) {
      return [
        `id:${parentIdByAbbreviation[document]}-${chapter}-rejections-${article.split('').slice(1).join('')}`,
      ];
    }
    if (article && !article.toLowerCase().includes('r')) {
      return [
        `id:${parentIdByAbbreviation[document]}-${chapter}-articles-${article}`,
      ];
    }
    return [
      [
        `parent:${parentIdByAbbreviation[document]}-${chapter}-articles`,
        `parent:${parentIdByAbbreviation[document]}-${chapter}-rejections`,
      ],
    ];
  }
  if (document && chapter && documentId && DOCUMENTS_WITHOUT_ARTICLES.includes(documentId)) {
    return [`id:${parentIdByAbbreviation[document]}-${chapter}`];
  }
  if (document && chapter && article) return [`id:${parentIdByAbbreviation[document]}-${chapter}-${article}`];
  if (document && chapter) return [`parent:${parentIdByAbbreviation[document]}-${chapter}`];
  // new UX: when searching an entire confession, just return the first chapter
  // Users can iterate through the confession using the next/previous buttons
  if (document && isEmptyKeywordSearch(str)) {
    if (documentId && DOCUMENTS_WITHOUT_ARTICLES.includes(documentId)) return [`id:${parentIdByAbbreviation[document]}-1`];
    if (documentId === 'CD') {
      return [[
        `parent:${parentIdByAbbreviation[document]}-1-articles`,
        `parent:${parentIdByAbbreviation[document]}-1-rejections`,
      ]];
    }
    return [`parent:${parentIdByAbbreviation[document]}-1`];
  }
  if (document) return [`document:${confessionCitationByIndex[document][0]}`];
  // test for bible
  const bibleResult = str.match(bibleRegex);
  if (bibleResult && bibleResult.length) {
    const [book, citation] = bibleResult;
    if (!citation) return [`book:${toOsis(book)}`];
    const range = citation.trim().split('-');
    const isRange = range.length > 1;
    if (book && citation && isRange) {
      const [start, end] = range;
      const [startChapter, startVerse] = start.split(':');
      const endCitation = end.split(':');
      return [
        `book:${toOsis(book)}`,
        `startChapter:${startChapter}`,
        `startVerse:${startVerse}`,
        endCitation.length > 1 ? `endChapter:${endCitation[0]}` : null,
        endCitation.length > 1 ? `endVerse:${endCitation[1]}` : `endVerse:${endCitation[0]}`,
      ].filter((el): el is string => !!el);
    }
    if (book && citation) {
      const [startChapter, startVerse] = citation.trim().split(':');
      return [
        `book:${toOsis(book)}`,
        `startChapter:${startChapter}`,
        startVerse ? `startVerse:${startVerse}` : null,
      ].filter((el): el is string => !!el);
    }
  }
  return [];
};

export const isFacetLength = (search: string, length: number): boolean => search
  .split('.').length === length;

// strips the facet grammar out of a search string, leaving the free-text
// keyword query that goes to Algolia as `query`.
export const removeFacetSyntax = (search: string): string => search
  .replace(regexV2, '')
  .replace(bibleRegex, '')
  .replace(keyWords, '')
  .trim();

export const getDocumentId = (id: string): string => id.split('-')[0];

export const isDocumentId = (id: string): boolean => !id.includes('-');

export const groupContentByChapter = (
  content: ConfessionEntry[],
): Record<string, ConfessionEntry[]> => groupBy(content, (obj) => {
  if (isDocumentId(obj.parent)) return obj.id;
  if (getDocumentId(obj.id) === 'CoD') {
    return `CoD-${obj.parent.split('-')[1]}`;
  }
  return obj.parent;
});

export const isChapter = (confessionId: string, entries: ContentById): boolean => (
  // parent would then be the document
  confessionId.split('-').length === 2
    && entries[confessionId].isParent
    && !DOCUMENTS_WITHOUT_ARTICLES.includes(confessionId)
);

export const sliceConfessionId = (str: string, fragmentNumber: number): string => {
  const idAsArr = str.split('-');
  return idAsArr.slice(0, fragmentNumber).join('-');
};

const footnoteMarkerRegex = /\[[a-zA-Z0-9]+\]/g;

// strips ESV/proof-text footnote markers (e.g. "[a]", "[12]") out of confession text
export const stripFootnoteMarkers = (text = ''): string => text
  .replace(footnoteMarkerRegex, '')
  .replace(/\s+/g, ' ')
  .trim();

// produces a clean, length-bounded string suitable for a meta description
export const truncateForMeta = (text = '', maxLength = 160): string => {
  const clean = stripFootnoteMarkers(text);
  if (clean.length <= maxLength) return clean;
  const truncated = clean.slice(0, maxLength);
  const lastSpace = truncated.lastIndexOf(' ');
  return `${truncated.slice(0, lastSpace > 0 ? lastSpace : maxLength)}…`;
};

// compares two entry ids (e.g. "WCoF-1-2", "CoD-1-articles-3") in document order,
// comparing each dash-separated fragment numerically where possible. Used to
// build a real, crawlable prev/next path across every entry in a document.
export const compareEntryIds = (aId: string, bId: string): number => {
  const a = aId.split('-').slice(1);
  const b = bId.split('-').slice(1);
  const len = Math.max(a.length, b.length);
  for (let i = 0; i < len; i += 1) {
    const [av, bv] = [a[i], b[i]];
    if (av === undefined) return -1;
    if (bv === undefined) return 1;
    const [aNum, bNum] = [Number(av), Number(bv)];
    const [aIsNum, bIsNum] = [!Number.isNaN(aNum), !Number.isNaN(bNum)];
    if (aIsNum && bIsNum) {
      if (aNum !== bNum) return aNum - bNum;
    } else if (av !== bv) {
      return av < bv ? -1 : 1;
    }
  }
  return 0;
};
