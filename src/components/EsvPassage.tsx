'use client';

// The scripture text on /scripture/[osis]. Fetched client-side through
// /api/esv rather than at build so 2,500+ static pages don't hammer the ESV
// API; degrades to nothing (the citation heading stands alone) without a key.
import { useEffect, useState } from 'react';

import { fetchEsvText } from '@/lib/esvClient';

export function EsvPassage({ osis }: { osis: string }) {
  const [text, setText] = useState<string | null | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    fetchEsvText(osis).then((result) => {
      if (!cancelled) setText(result);
    });
    return () => {
      cancelled = true;
    };
  }, [osis]);

  if (text === undefined) return <div className="min-h-16" aria-hidden="true" />;
  if (text === null) return null;

  return (
    <blockquote className="m-0 font-body text-[17px] italic leading-[1.55] text-ink">
      {text}
      <span className="label-caps ml-2 text-[8.5px] not-italic tracking-[0.1em] text-ink-3">ESV</span>
    </blockquote>
  );
}
