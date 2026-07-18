'use client';

// The daypart service (mockups 11b–11i), rendered by the shared eight-step
// shell. Resolved once per visit so a service never changes mid-worship,
// even across midnight.
import { useMemo } from 'react';

import { WorshipShell } from '@/components/WorshipShell';
import { getService, type Daypart } from '@/lib/worship';

export function WorshipServiceClient({ daypart }: { daypart: Daypart }) {
  const service = useMemo(() => getService(daypart, new Date()), [daypart]);
  return (
    <WorshipShell
      steps={service.steps}
      baseHref={`/worship/${daypart}`}
      exitHref="/worship"
      handoffQuery={`worship=${daypart}`}
      returnName="Family Worship"
      finishHref={`/worship/${daypart}/complete`}
      finishLabel="Finish Worship"
    />
  );
}
