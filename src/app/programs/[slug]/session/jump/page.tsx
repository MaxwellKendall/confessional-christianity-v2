import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { JumpToQuestionClient } from './JumpToQuestionClient';

export const metadata: Metadata = {
  title: 'Jump to Question',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export default async function JumpToQuestionPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getProgram(slug)) notFound();
  return <JumpToQuestionClient slug={slug} />;
}
