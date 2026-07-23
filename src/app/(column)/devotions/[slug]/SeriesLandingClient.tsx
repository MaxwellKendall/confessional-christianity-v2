'use client';

// A series landing (mockup 16a): the whole arc laid out in order — parts
// done, the next one up, and whatever's still ahead — with one Continue
// that jumps to wherever the household left off, and every authored part
// also reachable directly from the list. Nothing is locked: order is a
// suggestion the sequence makes, not a gate the household has to clear —
// a household can read part 12 before part 3 if that's what they want. Only
// an unauthored part is unreachable, and that's a content gap, not a lock.
// No dates anywhere. Progress is device state, so the list's states and the
// button render after mount, like every other local-progress surface.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { partDevotion, seriesSourceLabel, type DevotionSeries } from '@/lib/devotionSeries';
import { currentPartDay, getSeriesCompletedDays } from '@/lib/localSeriesProgress';

export function SeriesLandingClient({ series }: { series: DevotionSeries }) {
  const [completed, setCompleted] = useState<number[] | null>(null);
  useEffect(() => {
    setCompleted(getSeriesCompletedDays(series.slug));
  }, [series.slug]);

  const sourceName = seriesSourceLabel(series);
  const total = series.parts.length;

  if (!completed) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const done = new Set(completed);
  const current = currentPartDay(completed, total);
  const currentDevotion = current === null ? null : partDevotion(series, current);

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex-1 px-6 pt-7 pb-2.5">
        <div className="text-center">
          <div className="label-caps mb-2.5 text-[9px] tracking-[0.14em] text-ochre">
            {sourceName} · A {total}-Part Series · {series.tagline}
          </div>
          <h1 className="m-0 mb-2.5 heading-page">{series.title}</h1>
          <p className="m-0 mb-5 font-body text-[13px] italic leading-[1.7] text-ink-2">
            {series.description}
          </p>
          <div className="label-caps mb-2 text-[10px] tracking-[0.12em] text-ink-3">
            {current === null ? `All ${total} parts complete` : `Part ${current} of ${total}`}
          </div>
          <div className="mx-auto mb-5.5 h-[3px] w-full bg-hairline" aria-hidden="true">
            <div className="h-full bg-ochre" style={{ width: `${(done.size / total) * 100}%` }} />
          </div>
        </div>

        <ol className="m-0 list-none p-0 text-left">
          {series.parts.map((part) => {
            const devotion = partDevotion(series, part.day);
            const isDone = done.has(part.day);
            const isCurrent = part.day === current;
            const label = `Part ${part.day} — ${part.title} (${part.citation})`;

            if (!devotion) {
              return (
                <li key={part.day}>
                  <div className="flex items-center gap-3 border-b border-fill px-3 py-2.5">
                    <span className="w-4 shrink-0" aria-hidden="true" />
                    <span className="font-body text-[13px] text-muted">
                      {label} — in preparation
                    </span>
                  </div>
                </li>
              );
            }

            if (isDone) {
              return (
                <li key={part.day}>
                  <Link
                    href={`/devotions/${devotion.slug}`}
                    className="flex items-center gap-3 border-b border-fill px-3 py-2.5 text-ink-3 no-underline"
                  >
                    <span className="w-4 shrink-0 text-center font-display text-[11px] text-ochre" aria-hidden="true">✓</span>
                    <span className="font-body text-[13px]">{label}</span>
                  </Link>
                </li>
              );
            }

            return (
              <li key={part.day}>
                <Link
                  href={`/devotions/${devotion.slug}`}
                  className={isCurrent
                    ? 'my-0.5 flex items-center gap-3 rounded-sm bg-fill px-3 py-3 text-ink no-underline'
                    : 'flex items-center gap-3 border-b border-fill px-3 py-2.5 text-ink no-underline'}
                >
                  <span
                    className={`w-4 shrink-0 text-center text-[10px] text-ochre ${isCurrent ? '' : 'opacity-60'}`}
                    aria-hidden="true"
                  >
                    {isCurrent ? '●' : '○'}
                  </span>
                  <span className={`font-body text-[13px] ${isCurrent ? 'font-semibold' : ''}`}>{label}</span>
                </Link>
              </li>
            );
          })}
        </ol>

        <p className="m-0 px-3 pt-4 text-center font-body text-[11px] italic leading-[1.6] text-muted">
          Every part is open — read in order, or jump to any part directly.
        </p>
      </div>

      <div className="border-t border-hairline px-6 pt-3.5 pb-9 text-center">
        {current === null ? (
          <span className="font-body text-[12.5px] italic text-ink-2">
            This household has prayed the whole series, beginning to end.
          </span>
        ) : currentDevotion ? (
          <Link href={`/devotions/${currentDevotion.slug}`} className="action-button">
            {done.size > 0 ? `Continue — Part ${current}` : 'Begin — Part 1'}
          </Link>
        ) : (
          <span className="font-body text-[12.5px] italic text-ink-2">
            {`Part ${current} is still being prepared — the series continues soon.`}
          </span>
        )}
      </div>
    </div>
  );
}
