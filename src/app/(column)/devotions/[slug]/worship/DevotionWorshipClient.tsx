'use client';

// A devotion run (mockup 15c's "Begin This Devotion"): the same eight-step
// shell as Family Worship, fed the devotion's fixed steps — nothing rotates,
// so the shell needs no date. A standalone devotion finishes back on its own
// landing; a series part records its completion — unlocking the next part
// (turn 16) — and finishes on the series page, where the household sees the
// order advance.
import { WorshipShell } from '@/components/WorshipShell';
import { seriesMembership } from '@/lib/devotionSeries';
import { getDevotion } from '@/lib/devotions';
import { recordSeriesPartCompletion } from '@/lib/localSeriesProgress';

export function DevotionWorshipClient({ slug }: { slug: string }) {
  const devotion = getDevotion(slug)!;
  const membership = seriesMembership(devotion);
  const finishHref = membership
    ? `/devotions/${membership.series.slug}`
    : `/devotions/${slug}`;
  const onFinish = membership
    ? () => recordSeriesPartCompletion(membership.series.slug, membership.part.day)
    : undefined;
  return (
    <WorshipShell
      steps={devotion.steps}
      baseHref={`/devotions/${slug}/worship`}
      exitHref={`/devotions/${slug}`}
      handoffQuery={`devotion=${slug}`}
      returnName="this devotion"
      finishHref={finishHref}
      finishLabel="Finish"
      onFinish={onFinish}
    />
  );
}
