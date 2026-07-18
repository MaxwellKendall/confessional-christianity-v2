'use client';

// A devotion run (mockup 15c's "Begin This Devotion"): the same eight-step
// shell as Family Worship, fed the devotion's fixed steps — nothing rotates,
// so the shell needs no date. Finishing returns to the devotion's landing.
import { WorshipShell } from '@/components/WorshipShell';
import { getDevotion } from '@/lib/devotions';

export function DevotionWorshipClient({ slug }: { slug: string }) {
  const devotion = getDevotion(slug)!;
  return (
    <WorshipShell
      steps={devotion.steps}
      baseHref={`/devotions/${slug}/worship`}
      exitHref={`/devotions/${slug}`}
      handoffQuery={`devotion=${slug}`}
      returnName="this devotion"
      finishHref={`/devotions/${slug}`}
      finishLabel="Finish"
    />
  );
}
