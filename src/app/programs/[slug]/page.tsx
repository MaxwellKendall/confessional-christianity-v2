import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { ProgramLandingClient } from './ProgramLandingClient';

interface Params {
  slug: string;
}

export const dynamicParams = false;

export function generateStaticParams(): Params[] {
  return PROGRAMS.map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { slug } = await params;
  const program = getProgram(slug);
  if (!program) return {};
  return {
    title: program.title,
    description: program.description,
    alternates: { canonical: `/programs/${slug}` },
  };
}

export default async function ProgramLandingPage({ params }: { params: Promise<Params> }) {
  const { slug } = await params;
  const program = getProgram(slug);
  if (!program) notFound();
  return <ProgramLandingClient slug={slug} />;
}
