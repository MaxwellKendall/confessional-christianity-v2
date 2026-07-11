'use client';

// Proof texts on an entry page, grouped by the footnote marker that anchors
// them to a clause of the text. Each citation expands in place to the ESV
// text (fetched through /api/esv on first open) and links to the reference's
// canonical /scripture page.
import Link from 'next/link';
import { useState } from 'react';

import { fetchEsvText } from '@/lib/esvClient';
import type { ProofTextGroup } from '@/lib/entryDisplay';

export function ProofTexts({ groups }: { groups: ProofTextGroup[] }) {
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [texts, setTexts] = useState<Record<string, string | null>>({});

  const toggle = (osis: string) => {
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(osis)) next.delete(osis);
      else next.add(osis);
      return next;
    });
    if (!(osis in texts)) {
      fetchEsvText(osis).then((text) => setTexts((prev) => ({ ...prev, [osis]: text })));
    }
  };

  return (
    <div className="flex flex-col gap-2.5">
      {groups.map((group) => (
        <div key={group.marker} className="flex gap-2.5">
          <span className="w-4 shrink-0 pt-px text-right font-body text-[11px] text-ink-3" aria-hidden="true">
            {group.marker}
          </span>
          <div className="min-w-0 grow">
            <div className="text-[13px] leading-[1.9] text-ink-2">
              {group.refs.map((ref, i) => {
                const expanded = open.has(ref.osis);
                return (
                  <span key={ref.osis}>
                    {i > 0 && ' · '}
                    <button
                      type="button"
                      aria-expanded={expanded}
                      onClick={() => toggle(ref.osis)}
                      className={`dotted-link cursor-pointer border-none bg-transparent p-0 font-body text-[13px] ${expanded ? 'text-ink' : 'text-ink-2'}`}
                    >
                      {ref.citation}
                    </button>
                  </span>
                );
              })}
            </div>
            {group.refs.filter((ref) => open.has(ref.osis)).map((ref) => (
              <div key={ref.osis} className="mt-2 mb-2 border-l border-hairline pl-3.5">
                <p className="m-0 font-body text-[12.5px] italic leading-relaxed text-ink-2">
                  {ref.osis in texts
                    ? (texts[ref.osis] ?? ref.citation)
                    : 'Loading…'}
                </p>
                <Link
                  href={`/scripture/${ref.osis}`}
                  className="label-caps dotted-link mt-1.5 inline-block text-[9px] tracking-[0.08em] text-ink-3"
                >
                  {ref.citation} across the confessions →
                </Link>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
