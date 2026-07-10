// Search against the existing Algolia indices — `aggregate` (confession
// text) and `citations` (scripture) — reused from v1 with no re-indexing.
// Browser-side with a search-only key; the Admin key stays confined to the
// indexing scripts and is never NEXT_PUBLIC_.
import { algoliasearch } from 'algoliasearch';

import { parseFacets, removeFacetSyntax } from './helpers';

export const HITS_PER_PAGE = 25;

export interface HighlightValue {
  value: string;
  matchedWords: string[];
}

export interface AggregateHit {
  objectID: string;
  index: 'aggregate';
  id: string;
  document: string;
  title: string;
  text: string;
  _highlightResult?: {
    title?: HighlightValue;
    text?: HighlightValue;
  };
}

export interface CitationHit {
  objectID: string;
  index: 'citations';
  citation: string;
  bibleText: string;
  citedBy: string[];
  _highlightResult?: {
    citation?: HighlightValue;
    bibleText?: HighlightValue;
  };
}

export interface SearchOutcome {
  confessionHits: AggregateHit[];
  bibleHits: CitationHit[];
  totalConfession: number;
  totalBible: number;
  hasMore: boolean;
}

const client = algoliasearch(
  process.env.NEXT_PUBLIC_ALGOLIA_APP_ID ?? '',
  process.env.NEXT_PUBLIC_ALGOLIA_SEARCH_KEY ?? '',
);

// One query fans out to both indices with the same parsed facetFilters,
// exactly as v1's multipleQueries did; the facet grammar decides which index
// actually matches.
export const searchConfessions = async (search: string, page = 0): Promise<SearchOutcome> => {
  const facetFilters = parseFacets(search);
  const query = removeFacetSyntax(search);

  const { results } = await client.search({
    requests: [
      {
        indexName: 'aggregate',
        query,
        page,
        hitsPerPage: HITS_PER_PAGE,
        facetFilters: facetFilters as never,
        attributesToHighlight: ['text', 'title'],
      },
      {
        indexName: 'citations',
        query,
        page,
        hitsPerPage: HITS_PER_PAGE,
        facetFilters: facetFilters as never,
        attributesToHighlight: ['citation', 'bibleText'],
      },
    ],
  });

  const byIndex = new Map<string, { hits: unknown[]; nbHits?: number; nbPages?: number }>();
  results.forEach((result) => {
    if ('index' in result && result.index) {
      byIndex.set(result.index, result as never);
    }
  });

  const aggregate = byIndex.get('aggregate');
  const citations = byIndex.get('citations');

  const hasMore = [aggregate, citations].some(
    (r) => r && page < (r.nbPages ?? 0) - 1,
  );

  return {
    confessionHits: (aggregate?.hits ?? []).map((h) => ({ ...(h as AggregateHit), index: 'aggregate' as const })),
    bibleHits: (citations?.hits ?? []).map((h) => ({ ...(h as CitationHit), index: 'citations' as const })),
    totalConfession: aggregate?.nbHits ?? 0,
    totalBible: citations?.nbHits ?? 0,
    hasMore,
  };
};
