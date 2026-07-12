import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { StartProgramClient } from './StartProgramClient';

export const metadata: Metadata = {
  title: 'Start the Shorter Catechism',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export default async function StartProgramPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getProgram(slug)) notFound();
  return <StartProgramClient slug={slug} />;
}
