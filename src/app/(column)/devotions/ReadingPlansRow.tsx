'use client';

// The devotions hub's reading-plan row (turn 19, ignoring its proposed
// global-nav tab): first-class and default among the hub's browse axes — it
// renders first, right after Featured, ahead of the axes grounded in a
// single passage or question — since walking straight through the canon is
// the most universal starting point. Progress is device state, so the
// server renders the plain pace/length line and this takes over with day
// counts after mount, like FeaturedSlot and SeriesLandingClient.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { currentPartDay } from '@/lib/localSeriesProgress';
import { getReadingPlanCompletedDays } from '@/lib/localReadingPlanProgress';
import { READING_PLANS } from '@/lib/readingPlans';

export function ReadingPlansRow() {
  const [progress, setProgress] = useState<Record<string, number[]> | null>(null);

  useEffect(() => {
    setProgress(Object.fromEntries(
      READING_PLANS.map((plan) => [plan.slug, getReadingPlanCompletedDays(plan.slug)]),
    ));
  }, []);

  return (
    <div className="flex gap-2.5 px-5 pt-2 pb-1">
      {READING_PLANS.map((plan) => {
        const completed = progress?.[plan.slug] ?? [];
        const current = progress ? currentPartDay(completed, plan.totalDays) : null;
        return (
          <Link
            key={plan.slug}
            href={`/devotions/reading-plans/${plan.slug}`}
            className="flex-1 rounded-sm bg-fill px-3.5 py-3.5 text-ink no-underline"
          >
            <div className="mb-0.5 font-display text-[12.5px] font-semibold text-ink-2">{plan.shortTitle}</div>
            <div className="font-body text-[11px] text-ink-3">
              {completed.length > 0 && current !== null
                ? `Day ${current} of ${plan.totalDays}`
                : `${plan.pace} · ${plan.totalDays} days`}
              {' '}
              <span className="text-ochre" aria-hidden="true">→</span>
            </div>
          </Link>
        );
      })}
    </div>
  );
}
