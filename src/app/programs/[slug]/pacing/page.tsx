import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { PacingClient } from './PacingClient';

export const metadata: Metadata = {
  title: 'Pacing',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export default async function PacingPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getProgram(slug)) notFound();
  return <PacingClient slug={slug} />;
}
