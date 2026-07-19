'use client';

// The hub's featured slot (mockup 15a, reworked in turn 16): when a series
// is in progress on this device, the editorial pick yields to a Continue
// card — part count, the up-next part by name — so returning users land
// back in the sequence instead of the top of the shelf. With nothing in
// progress (or a series finished), the editorial pick stands. Progress is
// device state, so the server renders the editorial card and the Continue
// card takes over after mount.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { getAllSeries, type DevotionSeries } from '@/lib/devotionSeries';
import { SEASONS, getFeaturedDevotion, groundingLabel } from '@/lib/devotions';
import { currentPartDay, getSeriesCompletedDays } from '@/lib/localSeriesProgress';

interface InProgress {
  series: DevotionSeries;
  current: number;
}

export function FeaturedSlot() {
  const [inProgress, setInProgress] = useState<InProgress | null>(null);
  useEffect(() => {
    for (const series of getAllSeries()) {
      const completed = getSeriesCompletedDays(series.slug);
      const current = currentPartDay(completed, series.parts.length);
      if (completed.length > 0 && current !== null) {
        setInProgress({ series, current });
        return;
      }
    }
  }, []);

  if (inProgress) {
    const { series, current } = inProgress;
    const seasonName = SEASONS.find((s) => s.slug === series.season)?.name ?? '';
    const upNext = series.parts[current - 1];
    return (
      <Link
        href={`/devotions/${series.slug}`}
        className="mx-5 mb-4 block rounded-sm bg-featured px-5 py-5.5 text-card no-underline"
      >
        <div className="label-caps mb-2 text-[9px] tracking-[0.1em] text-heart-reviewing">
          Continue · Part {current} of {series.parts.length}
        </div>
        <div className="mb-1.5 font-display text-[17px] font-semibold">
          {series.title}{seasonName ? `: ${seasonName}` : ''}
        </div>
        <div className="font-body text-[12.5px] italic leading-[1.55] text-featured-ink">
          Up next: {upNext.title} ({upNext.citation}) — the household&rsquo;s
          next step in this ordered series.
        </div>
      </Link>
    );
  }

  const featured = getFeaturedDevotion();
  return (
    <Link
      href={`/devotions/${featured.slug}`}
      className="mx-5 mb-4 block rounded-sm bg-featured px-5 py-5.5 text-card no-underline"
    >
      <div className="label-caps mb-2 text-[9px] tracking-[0.1em] text-heart-reviewing">
        Grounded in {groundingLabel(featured.grounding)}
      </div>
      <div className="mb-1.5 font-display text-[17px] font-semibold">{featured.title}</div>
      <div className="font-body text-[12.5px] italic leading-[1.55] text-featured-ink">
        {featured.summary}
      </div>
    </Link>
  );
}
