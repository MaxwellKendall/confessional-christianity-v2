'use client';

// The /search surface (mockup 1d). Per PRD §7 this is the only page that may
// show match counts or the literal query; rows are short excerpts that link
// away to canonical pages.
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';

import {
  searchConfessions,
  type AggregateHit,
  type CitationHit,
  type SearchOutcome,
} from '@/lib/algolia';
import { citationToOsis } from '@/lib/bible';
import { generateCanonicalEntryLink, generateSearchLink, parseCitedById } from '@/lib/helpers';
import { SearchIcon } from './SearchIcon';

// Algolia highlight values arrive as HTML with <em> markers around matches;
// they originate from our own indexed confession text.
function Highlighted({ value, fallback }: { value?: string; fallback: string }) {
  if (!value) return <>{fallback}</>;
  return <span dangerouslySetInnerHTML={{ __html: value }} />;
}

function ConfessionRow({ hit }: { hit: AggregateHit }) {
  const href = generateCanonicalEntryLink(hit.id) ?? generateSearchLink(hit.id);
  return (
    <Link href={href} className="border-t border-hairline px-5 py-4 text-ink no-underline">
      <div className="label-caps mb-1 text-[9px] tracking-[0.1em] text-ink-3">{hit.document}</div>
      <div className="mb-1 font-display text-sm font-semibold">
        <Highlighted value={hit._highlightResult?.title?.value} fallback={hit.title} />
      </div>
      <div className="search-excerpt text-xs leading-relaxed text-ink-2">
        <Highlighted value={hit._highlightResult?.text?.value} fallback={hit.text} />
      </div>
    </Link>
  );
}

const CITED_BY_SHOWN = 4;

function CitationRow({ hit }: { hit: CitationHit }) {
  const osis = citationToOsis(hit.citation);
  const scriptureHref = osis ? `/scripture/${osis}` : null;
  // one link per citing entry, marker suffixes collapsed — the same entry can
  // cite a verse under several footnotes.
  const citedBy = Array.from(
    new Map((hit.citedBy ?? []).map((id) => {
      const cited = parseCitedById(id);
      return [cited.entryId, cited];
    })).values(),
  );
  const shown = citedBy.slice(0, CITED_BY_SHOWN);
  const remainder = citedBy.length - shown.length;

  return (
    <div className="border-t border-hairline px-5 py-4 text-ink">
      <div className="label-caps mb-1 text-[9px] tracking-[0.1em] text-ink-3">Scripture</div>
      <div className="mb-1 font-display text-sm font-semibold">
        {scriptureHref ? (
          <Link href={scriptureHref} className="text-ink no-underline">
            <Highlighted value={hit._highlightResult?.citation?.value} fallback={hit.citation} />
          </Link>
        ) : (
          <Highlighted value={hit._highlightResult?.citation?.value} fallback={hit.citation} />
        )}
      </div>
      <div className="search-excerpt line-clamp-4 text-xs leading-relaxed text-ink-2">
        <Highlighted value={hit._highlightResult?.bibleText?.value} fallback={hit.bibleText} />
      </div>
      {shown.length > 0 && (
        <div className="mt-2 text-xs leading-relaxed text-ink-2">
          <span className="label-caps text-[9px] tracking-[0.08em] text-ink-3">Cited by </span>
          {shown.map((cited, i) => (
            <span key={cited.entryId}>
              {i > 0 && ' · '}
              <Link
                href={generateCanonicalEntryLink(cited.entryId) ?? generateSearchLink(cited.entryId)}
                className="dotted-link text-ink"
              >
                {cited.label}
              </Link>
            </span>
          ))}
          {remainder > 0 && scriptureHref && (
            <span>
              {' · '}
              <Link href={scriptureHref} className="dotted-link text-ink-2">
                {remainder} more
              </Link>
            </span>
          )}
        </div>
      )}
    </div>
  );
}

export function SearchClient() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const initialQuery = searchParams.get('q') ?? '';

  const [input, setInput] = useState(initialQuery);
  const [outcome, setOutcome] = useState<SearchOutcome | null>(null);
  const [page, setPage] = useState(0);
  const [isLoading, setIsLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const runSearch = useCallback(async (query: string, nextPage: number) => {
    if (!query.trim()) {
      setOutcome(null);
      return;
    }
    setIsLoading(true);
    try {
      const result = await searchConfessions(query, nextPage);
      setOutcome((prev) => (nextPage > 0 && prev
        ? {
          ...result,
          confessionHits: [...prev.confessionHits, ...result.confessionHits],
          bibleHits: [...prev.bibleHits, ...result.bibleHits],
        }
        : result));
    } finally {
      setIsLoading(false);
    }
  }, []);

  // initial + URL-driven search
  useEffect(() => {
    setPage(0);
    runSearch(initialQuery, 0);
  }, [initialQuery, runSearch]);

  const onInputChange = (value: string) => {
    setInput(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      router.replace(value.trim() ? `/search?q=${encodeURIComponent(value)}` : '/search');
    }, 350);
  };

  const loadMore = () => {
    const nextPage = page + 1;
    setPage(nextPage);
    runSearch(initialQuery, nextPage);
  };

  const shown = outcome ? outcome.confessionHits.length + outcome.bibleHits.length : 0;
  const total = outcome ? outcome.totalConfession + outcome.totalBible : 0;

  return (
    <div className="pb-7">
      <div className="px-5 pt-6">
        <div className="label-caps mb-2.5 text-[9.5px] text-ink-3">Search</div>
        <div className="mb-3.5 flex items-center gap-2.5 border-b border-ink pb-2">
          <span className="text-ink"><SearchIcon /></span>
          <input
            type="search"
            value={input}
            onChange={(e) => onInputChange(e.target.value)}
            placeholder="Keyword, citation, or WSC.1"
            aria-label="Search the confessions"
            className="w-full bg-transparent font-body text-[15px] italic text-ink outline-none placeholder:text-muted"
          />
        </div>
        {outcome && (
          <div className="label-caps mb-4 text-[9.5px] tracking-[0.1em] text-ink-3">
            {isLoading ? 'Searching…' : `Showing ${Math.min(shown, total)} of ${total} total matches`}
          </div>
        )}
      </div>

      {outcome && (
        <div className="flex flex-col">
          {outcome.confessionHits.map((hit) => (
            <ConfessionRow key={hit.objectID} hit={hit} />
          ))}
          {outcome.bibleHits.map((hit) => (
            <CitationRow key={hit.objectID} hit={hit} />
          ))}
        </div>
      )}

      {outcome?.hasMore && (
        <div className="px-5 pt-5">
          <button type="button" onClick={loadMore} className="action-button w-full cursor-pointer bg-transparent">
            {isLoading ? 'Loading…' : 'More Results'}
          </button>
        </div>
      )}

      {!outcome && !isLoading && (
        <p className="px-8 pt-6 text-center text-[13px] italic leading-relaxed text-ink-2">
          Search by keyword, the text of Scripture, a citation like John 3:16,
          or a reference like WSC.1 or WCF.1.2.
        </p>
      )}
    </div>
  );
}
