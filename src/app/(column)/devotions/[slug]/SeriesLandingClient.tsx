'use client';

// A series landing (mockup 16a): the whole arc laid out in order — parts
// done, the current part, and the locked parts ahead — with one Continue
// that always resumes exactly where the household left off, never a
// re-pick from a list. A part unlocks when the one before it is finished;
// no dates anywhere. Progress is device state, so the list's states and
// the button render after mount, like every other local-progress surface.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { partDevotion, type DevotionSeries } from '@/lib/devotionSeries';
import { SEASONS } from '@/lib/devotions';
import { currentPartDay, getSeriesCompletedDays } from '@/lib/localSeriesProgress';

export function SeriesLandingClient({ series }: { series: DevotionSeries }) {
  const [completed, setCompleted] = useState<number[] | null>(null);
  useEffect(() => {
    setCompleted(getSeriesCompletedDays(series.slug));
  }, [series.slug]);

  const seasonName = SEASONS.find((s) => s.slug === series.season)?.name ?? series.title;
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
            {seasonName} · A {total}-Part Series · {series.tagline}
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
            const state = done.has(part.day) ? 'done'
              : part.day === current ? 'current'
                : 'locked';
            const devotion = state === 'locked' ? null : partDevotion(series, part.day);
            const label = `Part ${part.day} — ${part.title} (${part.citation})`;
            return (
              <li key={part.day}>
                {state === 'current' ? (
                  devotion ? (
                    <Link
                      href={`/devotions/${devotion.slug}`}
                      className="my-0.5 flex items-center gap-3 rounded-sm bg-fill px-3 py-3 text-ink no-underline"
                    >
                      <span className="w-4 shrink-0 text-center text-[10px] text-ochre" aria-hidden="true">●</span>
                      <span className="font-body text-[13px] font-semibold">{label}</span>
                    </Link>
                  ) : (
                    <div className="my-0.5 flex items-center gap-3 rounded-sm bg-fill px-3 py-3">
                      <span className="w-4 shrink-0 text-center text-[10px] text-ochre" aria-hidden="true">●</span>
                      <span className="font-body text-[13px] text-ink-2">
                        {label} — in preparation
                      </span>
                    </div>
                  )
                ) : state === 'done' && devotion ? (
                  <Link
                    href={`/devotions/${devotion.slug}`}
                    className="flex items-center gap-3 border-b border-fill px-3 py-2.5 text-ink-3 no-underline"
                  >
                    <span className="w-4 shrink-0 text-center font-display text-[11px] text-ochre" aria-hidden="true">✓</span>
                    <span className="font-body text-[13px]">{label}</span>
                  </Link>
                ) : (
                  <div className="flex items-center gap-3 border-b border-fill px-3 py-2.5">
                    <span className="w-4 shrink-0 text-center text-[10px] text-muted" aria-hidden="true">🔒</span>
                    <span className="font-body text-[13px] text-muted">{label}</span>
                  </div>
                )}
              </li>
            );
          })}
        </ol>

        <p className="m-0 px-3 pt-4 text-center font-body text-[11px] italic leading-[1.6] text-muted">
          Later parts unlock only once the one before is complete — the
          sequence, not the calendar, sets the pace.
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
