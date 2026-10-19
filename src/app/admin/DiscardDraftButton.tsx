'use client';

// Throws away a draft: closes its review PR unmerged and deletes the branch.
// What's published (if anything) is untouched.
import { useState, useTransition } from 'react';

import { discardDraft } from './actions';

export function DiscardDraftButton(
  { kind, slug, published }: { kind: 'devotion' | 'series'; slug: string; published: boolean },
) {
  const [error, setError] = useState<string | null>(null);
  const [discarding, start] = useTransition();
  const discard = () => {
    const message = published
      ? 'Discard these unmerged edits? The pull request closes and the published version stays as it is.'
      : `Discard "${slug}"? It was never published, so this deletes it: the pull request closes and its branch is removed.`;
    if (!window.confirm(message)) return;
    start(async () => {
      const result = await discardDraft(kind, slug);
      // on success the action redirects; a returned value is an error
      if (result?.error) setError(result.error);
    });
  };
  return (
    <span className="inline-flex items-baseline gap-2">
      <button
        type="button"
        onClick={discard}
        disabled={discarding}
        className="dotted-link cursor-pointer text-[12.5px] text-red-800 disabled:opacity-50"
      >
        {discarding ? 'Discarding…' : published ? 'Discard edits' : 'Discard draft'}
      </button>
      {error && <span className="text-[12px] text-red-800" role="alert">{error}</span>}
    </span>
  );
}
