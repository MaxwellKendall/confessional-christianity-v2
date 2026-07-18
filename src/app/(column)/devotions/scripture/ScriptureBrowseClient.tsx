'use client';

// Browse devotions by Scripture (mockup 15b): a search bar plus an A–Z
// index over all 66 books — not a curated sample — so the screen is
// genuinely extensible to the entire Bible. The chosen book expands to a
// range grid up top so a family can land on an exact chapter; books whose
// devotions are still unwritten stay listed, quiet and unlinked.
import Link from 'next/link';
import { useMemo, useState } from 'react';

import { BIBLE_BOOKS, type BibleBook } from '@/lib/bible';
import {
  groundingChapter, scriptureDevotionsByBook, type Devotion,
} from '@/lib/devotions';

function BookRow({
  book, devotionCount, onChoose,
}: { book: BibleBook; devotionCount: number; onChoose: () => void }) {
  const chapters = `${book.chapters} ${book.chapters === 1 ? 'chapter' : 'chapters'}`;
  if (devotionCount === 0) {
    return (
      <div className="flex justify-between border-t border-fill py-2.5 font-body text-[13.5px] text-ink-3">
        <span>{book.name}</span>
        <span className="text-[12px] italic">{chapters}</span>
      </div>
    );
  }
  return (
    <button
      type="button"
      onClick={onChoose}
      className="flex w-full cursor-pointer justify-between border-x-0 border-t border-b-0 border-solid border-fill bg-transparent px-0 py-2.5 text-left font-body text-[13.5px] text-ink"
    >
      <span>{book.name}</span>
      <span className="text-[12px] italic text-ochre">
        {chapters}
        {' · '}
        {devotionCount === 1 ? '1 devotion' : `${devotionCount} devotions`}
      </span>
    </button>
  );
}

export function ScriptureBrowseClient() {
  const byBook = useMemo(() => scriptureDevotionsByBook(), []);
  const defaultBook = BIBLE_BOOKS.find((b) => byBook.has(b.osis)) ?? null;

  const [query, setQuery] = useState('');
  const [chosen, setChosen] = useState<BibleBook | null>(defaultBook);

  // "1 Samuel" indexes under S, so the A–Z row is letters only.
  const letterOf = (name: string) => name.replace(/^[1-3] /, '')[0];
  const q = query.trim().toLowerCase();
  const visibleBooks = q.length === 1
    ? BIBLE_BOOKS.filter((b) => letterOf(b.name).toLowerCase() === q)
    : q
      ? BIBLE_BOOKS.filter((b) => b.name.toLowerCase().includes(q))
      : BIBLE_BOOKS;
  const letters = Array.from(new Set(BIBLE_BOOKS.map((b) => letterOf(b.name)))).sort();
  const chosenDevotions: Devotion[] = chosen ? (byBook.get(chosen.osis) ?? []) : [];

  const testament = (which: BibleBook['testament']) => visibleBooks
    .filter((b) => b.testament === which);

  return (
    <div className="px-5 pb-12">
      <div className="pt-6 pb-4 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">Devotions</div>
        <h1 className="mt-1.5 mb-1 heading-page">By Scripture</h1>
      </div>

      <div className="mb-4 flex items-center gap-2 rounded-full bg-fill px-4 py-2.5">
        <svg width="12" height="12" viewBox="0 0 20 20" aria-hidden="true">
          <circle cx="8" cy="8" r="6.5" fill="none" stroke="var(--color-ink-3)" strokeWidth="1.4" />
          <line x1="13" y1="13" x2="18" y2="18" stroke="var(--color-ink-3)" strokeWidth="1.4" />
        </svg>
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search any book, chapter, or verse…"
          aria-label="Search books"
          className="w-full border-none bg-transparent font-body text-[12.5px] italic text-ink outline-none placeholder:text-ink-3"
        />
      </div>

      {chosen && (
        <>
          <div className="label-caps mb-2.5 text-[9px] tracking-[0.14em] text-ochre">
            {chosen.name} · choose a range
          </div>
          {chosenDevotions.length > 0 ? (
            <div className="mb-5 grid grid-cols-6 gap-1.5">
              {chosenDevotions.map((devotion) => (
                <Link
                  key={devotion.slug}
                  href={`/devotions/${devotion.slug}`}
                  title={devotion.title}
                  className="rounded-sm bg-featured py-2 text-center font-display text-[12px] text-card no-underline"
                >
                  {groundingChapter(devotion.grounding) ?? '—'}
                </Link>
              ))}
            </div>
          ) : (
            <p className="m-0 mb-5 font-body text-[12px] italic text-ink-3">
              No devotions in {chosen.name} yet — the library grows toward all 66 books.
            </p>
          )}
        </>
      )}

      <div className="flex flex-wrap justify-center gap-1 border-t border-fill pt-2 pb-3" role="group" aria-label="Filter books by first letter">
        {letters.map((letter) => (
          <button
            key={letter}
            type="button"
            onClick={() => setQuery(query === letter ? '' : letter)}
            aria-pressed={q === letter.toLowerCase()}
            className={`cursor-pointer border-none bg-transparent px-1 py-0.5 font-display text-[9.5px] ${
              q === letter.toLowerCase() ? 'text-ochre' : 'text-ink-3'
            }`}
          >
            {letter}
          </button>
        ))}
      </div>
      <p className="m-0 mb-3.5 text-center font-body text-[11px] italic text-muted">
        All 66 books, Genesis through Revelation
      </p>

      {(['old', 'new'] as const).map((which) => {
        const books = testament(which);
        if (books.length === 0) return null;
        return (
          <div key={which} className="mb-4">
            <div className="label-caps mb-2 text-[9px] tracking-[0.14em] text-ink-3">
              {which === 'old' ? 'Old Testament' : 'New Testament'}
            </div>
            <div className="flex flex-col border-b border-fill">
              {books.map((book) => (
                <BookRow
                  key={book.osis}
                  book={book}
                  devotionCount={byBook.get(book.osis)?.length ?? 0}
                  onChoose={() => {
                    setChosen(book);
                    window.scrollTo({ top: 0 });
                  }}
                />
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}
