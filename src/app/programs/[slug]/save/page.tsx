import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { SaveProgressClient } from './SaveProgressClient';

export const metadata: Metadata = {
  title: 'Save Progress',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export default async function SaveProgressPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getProgram(slug)) notFound();
  return <SaveProgressClient slug={slug} />;
}
