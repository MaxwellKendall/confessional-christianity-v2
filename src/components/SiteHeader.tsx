import Link from 'next/link';

import { SearchIcon } from './SearchIcon';

// Primary nav per PRD §4: wordmark, Catechisms first among small-caps text
// links (Catechisms · Reflections · Library), search icon. No per-child
// switcher lives here (§5.5).
export function SiteHeader() {
  return (
    <header className="border-b border-hairline px-5 pt-4 pb-3.5 text-center">
      <div className="flex items-center justify-between">
        {/* spacer balancing the search icon so the wordmark stays centered */}
        <span className="w-[22px]" aria-hidden="true" />
        <Link
          href="/"
          className="font-display font-semibold text-[13.5px] tracking-[0.13em] uppercase text-ink no-underline"
        >
          Confessional Christianity
        </Link>
        <Link href="/search" aria-label="Search" className="p-1 text-ink">
          <SearchIcon />
        </Link>
      </div>
      <nav className="mt-3 flex justify-center gap-[22px] label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
        <Link href="/programs" className="text-ink no-underline">Catechisms</Link>
        <Link href="/reflections" className="text-ink-3 no-underline">Reflections</Link>
        <Link href="/library" className="text-ink-3 no-underline">Library</Link>
      </nav>
    </header>
  );
}
