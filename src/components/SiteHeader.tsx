import Link from 'next/link';

import { SearchIcon } from './SearchIcon';

// Primary nav per PRD §4: wordmark, Catechisms first among small-caps text
// links (Catechisms · Resources · Library), search icon. No per-child
// switcher lives here (§5.5). Sized for the phone frame at the base scale,
// stepping up with the full-bleed shell on wider screens.
export function SiteHeader() {
  return (
    <header className="border-b border-hairline px-5 pt-4 pb-3.5 text-center sm:px-10 sm:pt-6 sm:pb-5">
      <div className="flex items-center justify-between">
        {/* spacer balancing the search icon so the wordmark stays centered */}
        <span className="w-[22px]" aria-hidden="true" />
        <Link
          href="/"
          className="font-display font-semibold text-[13.5px] tracking-[0.13em] uppercase text-ink no-underline sm:text-[19px] sm:tracking-[0.16em]"
        >
          Confessional Christianity
        </Link>
        <Link href="/search" aria-label="Search" className="p-1 text-ink">
          <SearchIcon />
        </Link>
      </div>
      <nav className="mt-3 flex justify-center gap-[22px] label-caps text-[9.5px] tracking-[0.1em] text-ink-3 sm:mt-4 sm:gap-9 sm:text-[11.5px]">
        <Link href="/programs" className="text-ink no-underline">Catechisms</Link>
        <Link href="/reflections" className="text-ink-3 no-underline">Resources</Link>
        <Link href="/library" className="text-ink-3 no-underline">Library</Link>
      </nav>
    </header>
  );
}
