'use client';

// The share sheet: a preview of the image that will be shared (the same one
// the link unfurls into), the words as they'll read, and the actions.
import { useEffect, useMemo } from 'react';

import { ShareActions } from '@/components/ShareActions';
import type { ConfessionEntry } from '@/lib/domain';
import { buildShareQuote, shareImagePath, sharePath, shareText, type ShareSelection } from '@/lib/share';

export function ShareSheet(
  { entry, slug, segment, selection, source, onClose }: {
    entry: ConfessionEntry;
    slug: string;
    segment: string;
    selection: ShareSelection;
    source: string;
    onClose: () => void;
  },
) {
  const quote = useMemo(() => buildShareQuote(entry, selection), [entry, selection]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    const { overflow } = document.body.style;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = overflow;
    };
  }, [onClose]);

  if (!quote) return null;
  const path = sharePath(slug, segment, quote.selection);
  const heading = selection.kind === 'clause' ? 'Share this clause' : selection.kind === 'range' ? 'Share this quote' : 'Share';

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/40 sm:items-center"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label={heading}
        className="max-h-[92dvh] w-full max-w-[30rem] overflow-y-auto rounded-t-lg bg-card px-5 pt-4 pb-6 shadow-frame sm:rounded-lg"
      >
        <div className="mb-3 flex items-center justify-between">
          <span className="label-caps text-[10px] tracking-[0.12em] text-ink">{heading}</span>
          <button type="button" onClick={onClose} className="cursor-pointer px-1 text-[20px] leading-none text-ink-3" aria-label="Close">
            ×
          </button>
        </div>
        {/* eslint-disable-next-line @next/next/no-img-element -- a generated image, not a static asset */}
        <img
          src={shareImagePath(path, 'og')}
          alt={`${quote.question ? `Q. ${quote.question} A. ` : ''}${quote.quote} — ${source}`}
          width={1200}
          height={630}
          className="block h-auto w-full rounded-sm border border-hairline bg-fill"
        />
        {quote.refs.length > 0 && (
          <p className="m-0 mt-2.5 text-center font-body text-[12px] italic text-ink-3">
            With {quote.refs.map((r) => r.citation).join(' · ')}
          </p>
        )}
        <div className="mt-4">
          <ShareActions
            autoFocus
            target={{ path, title: source, text: shareText(quote, { source }) }}
          />
        </div>
      </div>
    </div>
  );
}
