'use client';

// The share buttons, wherever a quote is shared from. "Share…" hands the
// device's share sheet the portrait image itself when it can take files
// (phones: Messages, Instagram, Photos), else the link with its text; the
// link unfurls into the landscape preview image anywhere it's pasted.
import { useEffect, useState } from 'react';

import { shareImagePath } from '@/lib/share';

export interface ShareTarget {
  /** Relative share URL, e.g. /share/westminster-shorter-catechism/1?c=a */
  path: string;
  /** Plain-text version of the quote (for Copy text and the share text). */
  text: string;
  title: string;
}

const buttonClass = 'flex-1 cursor-pointer rounded-md border border-hairline bg-card px-3 py-2.5 label-caps text-[10px] tracking-[0.1em] text-ink hover:bg-fill disabled:opacity-50';

export function ShareActions({ target, autoFocus = false }: { target: ShareTarget; autoFocus?: boolean }) {
  const [note, setNote] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [canShare, setCanShare] = useState(false);
  useEffect(() => setCanShare(typeof navigator !== 'undefined' && typeof navigator.share === 'function'), []);

  const absolute = (relative: string) => new URL(relative, window.location.origin).toString();
  const flash = (message: string) => {
    setNote(message);
    window.setTimeout(() => setNote(null), 2200);
  };

  const copy = async (value: string, done: string) => {
    try {
      await navigator.clipboard.writeText(value);
      flash(done);
    } catch {
      flash('Copying isn’t allowed here — select and copy the text instead.');
    }
  };

  const shareNative = async () => {
    const url = absolute(target.path);
    setBusy(true);
    try {
      // the image is the share on phones; fall back to the link everywhere else
      try {
        const response = await fetch(shareImagePath(target.path, 'portrait'));
        const blob = await response.blob();
        const file = new File([blob], 'confessional-christianity.png', { type: 'image/png' });
        if (response.ok && navigator.canShare?.({ files: [file] })) {
          await navigator.share({ files: [file], title: target.title, text: `${target.text}\n\n${url}` });
          return;
        }
      } catch (error) {
        if (error instanceof DOMException && error.name === 'AbortError') return;
      }
      await navigator.share({ title: target.title, text: target.text, url });
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'AbortError')) flash('Sharing didn’t work — try Copy link.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap gap-2">
        {canShare && (
          <button type="button" className={`${buttonClass} bg-ink text-card hover:bg-ink`} onClick={shareNative} disabled={busy} autoFocus={autoFocus}>
            {busy ? 'Preparing…' : 'Share…'}
          </button>
        )}
        <button type="button" className={buttonClass} onClick={() => copy(absolute(target.path), 'Link copied')}>
          Copy link
        </button>
        <button type="button" className={buttonClass} onClick={() => copy(`${target.text}\n\n${absolute(target.path)}`, 'Text copied')}>
          Copy text
        </button>
        <a
          className={`${buttonClass} text-center no-underline`}
          href={shareImagePath(target.path, 'portrait')}
          download="confessional-christianity.png"
        >
          Save image
        </a>
      </div>
      <p className="m-0 min-h-[1.2em] text-center text-[12px] text-ink-3" role="status" aria-live="polite">{note}</p>
    </div>
  );
}
