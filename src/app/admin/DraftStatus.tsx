'use client';

// The line under an editor's title: where the live version is, and the open
// review PR (with a way to throw it away) when there are unmerged edits.
import Link from 'next/link';

import { DiscardDraftButton } from './DiscardDraftButton';

export function DraftStatus(
  { kind, slug, creating, published, pending }: {
    kind: 'devotion' | 'series';
    slug: string;
    creating: boolean;
    published: boolean;
    pending: { url: string; number: number } | null;
  },
) {
  if (creating) return <p className="m-0 mt-1 text-[13px] text-ink-3">Not saved yet.</p>;
  return (
    <p className="m-0 mt-1 flex flex-wrap items-baseline gap-x-3 gap-y-1 text-[13px] text-ink-3">
      {published && (
        <span>
          Live at{' '}
          <Link href={`/devotions/${slug}`} target="_blank" className="text-ink-2">/devotions/{slug} ↗</Link>
        </span>
      )}
      {pending && (
        <>
          <span>
            {published ? 'Unmerged edits' : 'Not published yet — in review'} in{' '}
            <a href={pending.url} target="_blank" rel="noreferrer" className="text-ochre">pull request #{pending.number} ↗</a>
            {' '}— the next save adds to it.
          </span>
          <DiscardDraftButton kind={kind} slug={slug} published={published} />
        </>
      )}
    </p>
  );
}
