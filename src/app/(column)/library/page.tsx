import type { Metadata } from 'next';
import Link from 'next/link';

import { LIBRARY_DOCUMENTS } from '@/lib/library';

export const metadata: Metadata = {
  title: 'Library',
  description:
    'The confessions and catechisms of historic Protestantism — the Westminster '
    + 'Standards, the Three Forms of Unity, the Thirty-Nine Articles, and '
    + 'Luther’s Ninety-Five Theses — to read in full.',
  alternates: { canonical: '/library' },
};

export default function LibraryPage() {
  return (
    <div className="pb-7">
      <div className="px-5 pt-6 text-center">
        <h1 className="heading-page">Library</h1>
      </div>

      <div className="mt-5 flex flex-col px-5">
        {LIBRARY_DOCUMENTS.map((doc) => (
          <Link
            key={doc.slug}
            href={`/library/${doc.slug}`}
            className="border-t border-hairline py-[13px] text-ink no-underline"
          >
            <div className="mb-1 font-display text-sm font-semibold">{doc.name}</div>
            <div className="text-xs italic text-ink-2">{doc.blurb}</div>
          </Link>
        ))}
      </div>

      <div className="mx-5 mt-4 border-t border-hairline pt-4 text-center">
        <span className="text-[13px] italic text-ink-2">
          New here? Start with the{' '}
          <Link href="/library/westminster-shorter-catechism" className="dotted-link text-ink">
            Shorter Catechism
          </Link>
          .
        </span>
      </div>
    </div>
  );
}
