import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';

import type { Daypart } from '@/lib/worship';
import { WorshipServiceClient } from './WorshipServiceClient';

export const metadata: Metadata = {
  title: 'Family Worship',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { daypart: Daypart }[] {
  return [{ daypart: 'morning' }, { daypart: 'evening' }];
}

export default async function WorshipServicePage(
  { params }: { params: Promise<{ daypart: string }> },
) {
  const { daypart } = await params;
  if (daypart !== 'morning' && daypart !== 'evening') notFound();
  return (
    <Suspense fallback={<div className="min-h-64" aria-hidden="true" />}>
      <WorshipServiceClient daypart={daypart} />
    </Suspense>
  );
}
