import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { StartProgramClient } from './StartProgramClient';

export const dynamicParams = false;

export function generateStaticParams(): { slug: string }[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<{ slug: string }> },
): Promise<Metadata> {
  const { slug } = await params;
  const program = getProgram(slug);
  return {
    title: program ? `Start ${program.title}` : 'Start a Catechism',
    robots: { index: false },
  };
}

export default async function StartProgramPage(
  { params }: { params: Promise<{ slug: string }> },
) {
  const { slug } = await params;
  if (!getProgram(slug)) notFound();
  return <StartProgramClient slug={slug} />;
}
