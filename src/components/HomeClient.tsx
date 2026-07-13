'use client';

// Homepage: no name/age capture, no held screen — straight into Question 1
// (or wherever a returning visitor left off). Progress lives on this device.
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

import { getLocalCatechismTrack, startLocalCatechismTrack } from '@/lib/localCatechismProgress';
import { PROGRAMS } from '@/lib/programs';

const PROGRAM = PROGRAMS[0];

export function HomeClient() {
  const router = useRouter();

  useEffect(() => {
    if (!getLocalCatechismTrack(PROGRAM.contentId)) {
      startLocalCatechismTrack(PROGRAM.contentId, 1);
    }
    router.replace(`/programs/${PROGRAM.slug}/session`);
  }, [router]);

  return <div className="min-h-40" aria-hidden="true" />;
}
