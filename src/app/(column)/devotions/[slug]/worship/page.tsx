import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';

import { getAllDevotions, getDevotion } from '@/lib/devotions';
import { DevotionWorshipClient } from './DevotionWorshipClient';

export const metadata: Metadata = {
  title: 'Devotion',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return getAllDevotions().map(({ slug }) => ({ slug }));
}

export default async function DevotionWorshipPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getDevotion(slug)) notFound();
  return (
    <Suspense fallback={<div className="min-h-64" aria-hidden="true" />}>
      <DevotionWorshipClient slug={slug} />
    </Suspense>
  );
}
