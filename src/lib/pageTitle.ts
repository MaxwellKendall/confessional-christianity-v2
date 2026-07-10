// getPageTitle and its subtitle lookup, split out of helpers.ts because they
// read the full content-by-id map (~700K) — server-side only; never import
// from a client component.
import { capitalize, startCase } from 'lodash-es';

import {
  confessionCitationByIndex,
  facetNamesByCanonicalDocId,
  parentIdByAbbreviation,
} from './dataMapping';
import {
  bibleRegex,
  getCanonicalDocId,
  keyWords,
  regexTest,
  regexV2,
} from './helpers';
import type { ContentById } from './domain';
import contentByIdJson from '../../dataMapping/content-by-id.json';

const contentById = contentByIdJson as unknown as ContentById;

const documentPrefix = /question\s[0-9]{1,}:\s|chapter\s[0-9]{1,}:\s|article\s[0-9]{1,}:\s|rejection\s[0-9]{1,}:\s/ig;

const removeDot = (str: string | null): string | null => (str ? str.replaceAll('.', '') : str);

const removePrefix = (str: string | undefined): string | undefined => {
  if (str) {
    return str.replace(documentPrefix, '');
  }
  return undefined;
};

const getSubTitleFromConfession = (
  query: string | null,
  docId: string,
  chapterId: string,
  articleId?: string,
): string | null | undefined => {
  if (query) return query;
  const confessionId = `${docId}-${chapterId}`;
  if (confessionId.startsWith('HC') && chapterId && !articleId) {
    // title is just LORD's Day X
    return '';
  }
  if (confessionId.startsWith('HC') && chapterId && articleId) {
    const key = `${confessionId}-${articleId}`;
    // title is actually useful, return it
    if (contentById[key]) {
      return removePrefix(contentById[`${confessionId}-${articleId}`].title);
    }
  }

  if (contentById[confessionId]) return removePrefix(contentById[confessionId].title);
  return undefined;
};

// Pure function: derives the [title, subtitle] copy for a given search string.
export const getPageTitle = (search?: string): [string, string | null | undefined] => {
  if (!search) return ['Search the Confessions of Historic Protestantism', 'By Keyword, Scripture Text, or Citation'];
  let queryWithoutFacetFilters: string | null = `${search.replace(regexV2, '').replace(keyWords, '').replace(bibleRegex, '')}` || null;
  queryWithoutFacetFilters = queryWithoutFacetFilters ? `search results for "${startCase(queryWithoutFacetFilters)}"` : queryWithoutFacetFilters;
  const result = search.match(regexV2);
  const doc = (result && result.length && getCanonicalDocId(result[0])) || null;
  const chap = (doc && result && result.length > 1 && `${facetNamesByCanonicalDocId[doc][0]} ${removeDot(result[1])}`) || null;
  const art = (doc && result && result.length > 2 && `${facetNamesByCanonicalDocId[doc][1]} ${removeDot(result[2])}`) || null;
  if (doc && chap && art && result) {
    const subTitle = getSubTitleFromConfession(
      queryWithoutFacetFilters,
      parentIdByAbbreviation[doc],
      removeDot(result[1]) as string,
      removeDot(result[2]) as string,
    );
    return [`${confessionCitationByIndex[doc][0]} ${startCase(chap.toLowerCase())} ${startCase(art.toLowerCase())}`, subTitle];
  }
  if (doc && chap && result) {
    const subTitle = getSubTitleFromConfession(
      queryWithoutFacetFilters,
      parentIdByAbbreviation[doc],
      removeDot(result[1]) as string,
    );
    return [`${confessionCitationByIndex[doc][0]} ${startCase(chap.toLowerCase())}`, subTitle];
  }
  if (doc) {
    return [`${confessionCitationByIndex[doc][0]}`, queryWithoutFacetFilters];
  }
  if (regexTest(keyWords, search)) {
    return [`The ${startCase((search.match(keyWords) as RegExpMatchArray)[0].toLowerCase())}`, queryWithoutFacetFilters];
  }
  if (regexTest(bibleRegex, search)) {
    return [
      (search.match(bibleRegex) as RegExpMatchArray).map((s) => capitalize(s)).join(' ').replace(/\s+/g, ' ').trim(),
      queryWithoutFacetFilters,
    ];
  }
  return ['', queryWithoutFacetFilters];
};
