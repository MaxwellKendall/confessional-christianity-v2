'use client';

// The library entry's quote and proof texts, made shareable. Three ways in:
// - tap a clause (the words before a footnote marker) to pick it, which
//   lights up its proof texts and offers "Share this clause";
// - select any run of words, which floats a "Share quote" button;
// - "Share" under the quote shares the whole entry.
// A shared link's "read in context" lands here with #c-<marker> or
// #r-<start>-<end>, and the reader highlights what was shared.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';

import { ProofTexts } from '@/components/ProofTexts';
import { ShareSheet } from '@/components/ShareSheet';
import type { ConfessionEntry } from '@/lib/domain';
import type { ProofTextGroup } from '@/lib/entryDisplay';
import { clauseSpans, type ShareSelection } from '@/lib/share';

const QUESTION_PREFIX = /^Question\s(\d+):\s*/;

/** Reads #c-a / #r-12-40 back into a selection. */
const selectionFromHash = (hash: string): ShareSelection | null => {
  const clause = hash.match(/^#c-([A-Za-z0-9]{1,4})$/);
  if (clause) return { kind: 'clause', marker: clause[1] };
  const range = hash.match(/^#r-(\d+)-(\d+)$/);
  if (range && Number(range[2]) > Number(range[1])) {
    return { kind: 'range', start: Number(range[1]), end: Number(range[2]) };
  }
  return null;
};

/** Character offset of (node, offset) within `root`'s reading text —
 * counting only answer text, never the footnote superscripts. Measured with
 * a Range, so element boundaries (a triple-click) resolve exactly too. */
const textOffset = (root: HTMLElement, node: Node, offset: number): number | null => {
  if (!root.contains(node)) return null;
  const range = document.createRange();
  range.setStart(root, 0);
  range.setEnd(node, offset);
  const fragment = range.cloneContents();
  fragment.querySelectorAll('[data-skip]').forEach((el) => el.remove());
  return fragment.textContent?.length ?? 0;
};

interface FloatingButton {
  top: number;
  left: number;
  range: { start: number; end: number };
}

export function EntryReader(
  { entry, slug, segment, proofTexts, source }: {
    entry: ConfessionEntry;
    slug: string;
    segment: string;
    proofTexts: ProofTextGroup[];
    source: string;
  },
) {
  const spans = useMemo(() => clauseSpans(entry), [entry]);
  const question = entry.title?.match(QUESTION_PREFIX) ? entry.title.replace(QUESTION_PREFIX, '') : null;
  const answerRef = useRef<HTMLSpanElement>(null);
  const [picked, setPicked] = useState<ShareSelection | null>(null);
  const [floating, setFloating] = useState<FloatingButton | null>(null);
  const [sheet, setSheet] = useState<ShareSelection | null>(null);

  // arriving from a shared link: highlight what was shared
  useEffect(() => {
    const fromHash = selectionFromHash(window.location.hash);
    if (fromHash) {
      setPicked(fromHash);
      answerRef.current?.scrollIntoView({ block: 'center' });
    }
  }, []);

  // a text selection inside the answer floats a share button over it
  const onSelectionChange = useCallback(() => {
    const root = answerRef.current;
    const selection = window.getSelection();
    if (!root || !selection || selection.isCollapsed || selection.rangeCount === 0) {
      setFloating(null);
      return;
    }
    const range = selection.getRangeAt(0);
    if (!root.contains(range.commonAncestorContainer)) {
      setFloating(null);
      return;
    }
    const start = textOffset(root, range.startContainer, range.startOffset);
    const end = textOffset(root, range.endContainer, range.endOffset);
    if (start === null || end === null || end - start < 3) {
      setFloating(null);
      return;
    }
    const box = range.getBoundingClientRect();
    setFloating({
      top: box.bottom + window.scrollY + 10,
      left: Math.min(Math.max(box.left + box.width / 2 + window.scrollX, 80), window.innerWidth - 80),
      range: { start, end },
    });
  }, []);

  useEffect(() => {
    document.addEventListener('selectionchange', onSelectionChange);
    return () => document.removeEventListener('selectionchange', onSelectionChange);
  }, [onSelectionChange]);

  const pickClause = (marker: string) => {
    // a click that ends a drag-selection is a selection, not a pick
    if (!window.getSelection()?.isCollapsed) return;
    setPicked((current) => (current?.kind === 'clause' && current.marker === marker ? null : { kind: 'clause', marker }));
  };

  const highlighted = (start: number, end: number): boolean => {
    if (!picked || picked.kind === 'entry') return false;
    if (picked.kind === 'clause') {
      const span = spans.find((s) => s.marker === picked.marker);
      return Boolean(span && start >= span.start && end <= span.end);
    }
    return start < picked.end && end > picked.start;
  };

  /** A span's text split at the picked range's edges, so a selection that
   * starts mid-clause highlights from exactly where it starts. */
  const pieces = (start: number, text: string) => {
    if (picked?.kind !== 'range') return [{ text, on: highlighted(start, start + text.length) }];
    const cuts = [0, picked.start - start, picked.end - start, text.length]
      .filter((c) => c >= 0 && c <= text.length)
      .sort((a, b) => a - b);
    const out: { text: string; on: boolean }[] = [];
    for (let i = 0; i < cuts.length - 1; i += 1) {
      if (cuts[i + 1] > cuts[i]) {
        const pieceText = text.slice(cuts[i], cuts[i + 1]);
        out.push({ text: pieceText, on: highlighted(start + cuts[i], start + cuts[i + 1]) });
      }
    }
    return out;
  };

  const activeMarkers = useMemo(() => {
    if (!picked || picked.kind === 'entry') return [];
    if (picked.kind === 'clause') return [picked.marker];
    return spans.filter((s) => s.marker && s.start < picked.end && s.end > picked.start).map((s) => s.marker!);
  }, [picked, spans]);

  const openSheet = (selection: ShareSelection) => {
    window.getSelection()?.removeAllRanges();
    setFloating(null);
    setSheet(selection);
  };

  const pickedLabel = picked?.kind === 'clause' ? 'Share this clause' : picked?.kind === 'range' ? 'Share this quote' : null;

  return (
    <>
      <div className="px-11 pt-4 text-center">
        <blockquote className="m-0 font-body text-[17px] italic leading-[1.55] text-ink">
          {question && <span>Q. {question}<br /></span>}
          {question && 'A. '}
          <span ref={answerRef}>
            {spans.map((span) => (
              <span
                key={span.start}
                onClick={span.marker ? () => pickClause(span.marker!) : undefined}
                className={span.marker ? 'cursor-pointer' : undefined}
                title={span.marker ? 'Tap to pick this clause and its Scripture' : undefined}
              >
                {pieces(span.start, span.text).map((piece, i) => (
                  <span
                    key={i}
                    className={piece.on ? 'rounded-[2px] bg-[#f1e5cc] box-decoration-clone text-ink' : undefined}
                  >
                    {piece.text}
                  </span>
                ))}
                {span.marker && (
                  <sup data-skip className={`font-body text-[10.5px] not-italic ${activeMarkers.includes(span.marker) ? 'text-ochre' : 'text-ink-3'}`}>
                    {span.marker}
                  </sup>
                )}
              </span>
            ))}
          </span>
        </blockquote>

        <div className="mt-4 flex flex-wrap items-center justify-center gap-x-4 gap-y-2 label-caps text-[9.5px] tracking-[0.1em]">
          {picked && pickedLabel ? (
            <>
              <button type="button" onClick={() => openSheet(picked)} className="cursor-pointer rounded-sm bg-ink px-3 py-1.5 text-card">
                {pickedLabel}
              </button>
              <button type="button" onClick={() => setPicked(null)} className="dotted-link cursor-pointer text-ink-3">
                Clear
              </button>
            </>
          ) : (
            <button type="button" onClick={() => openSheet({ kind: 'entry' })} className="dotted-link cursor-pointer text-ink">
              Share
            </button>
          )}
        </div>
        {!picked && spans.some((s) => s.marker) && (
          <p className="m-0 mt-2 font-body text-[11.5px] italic text-muted">
            Tap a clause to share it with its Scripture, or select any words.
          </p>
        )}
      </div>

      {floating && createPortal(
        <button
          type="button"
          // mousedown would collapse the selection before the click lands
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => openSheet({ kind: 'range', ...floating.range })}
          style={{ position: 'absolute', top: floating.top, left: floating.left, transform: 'translateX(-50%)' }}
          className="z-30 cursor-pointer rounded-full bg-ink px-4 py-2 label-caps text-[10px] tracking-[0.1em] text-card shadow-frame"
        >
          Share quote
        </button>,
        document.body,
      )}

      {proofTexts.length > 0 && (
        <div className="mx-5 mt-6 border-t border-hairline pt-4">
          <div className="label-caps mb-2 text-[9.5px] text-ink-3">Proof Texts</div>
          <ProofTexts groups={proofTexts} highlight={activeMarkers} />
        </div>
      )}

      {sheet && (
        <ShareSheet
          entry={entry}
          slug={slug}
          segment={segment}
          selection={sheet}
          source={source}
          onClose={() => setSheet(null)}
        />
      )}
    </>
  );
}
