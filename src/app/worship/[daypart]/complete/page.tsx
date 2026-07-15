import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import type { Daypart } from '@/lib/worship';
import { WorshipCompleteClient } from './WorshipCompleteClient';

export const metadata: Metadata = {
  title: 'Worship Complete',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { daypart: Daypart }[] {
  return [{ daypart: 'morning' }, { daypart: 'evening' }];
}

export default async function WorshipCompletePage(
  { params }: { params: Promise<{ daypart: string }> },
) {
  const { daypart } = await params;
  if (daypart !== 'morning' && daypart !== 'evening') notFound();
  return <WorshipCompleteClient daypart={daypart} />;
}
