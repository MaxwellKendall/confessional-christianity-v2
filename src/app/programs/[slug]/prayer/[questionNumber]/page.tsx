import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';

import { getProgram, PROGRAMS } from '@/lib/programs';
import { getQuestion } from '@/lib/programContent';
import { PrayerClient } from './PrayerClient';

export const metadata: Metadata = {
  title: 'Pray About This',
  robots: { index: false },
};

export const dynamicParams = false;

export function generateStaticParams(): { slug: string; questionNumber: string }[] {
  return PROGRAMS.flatMap(({ slug, totalQuestions }) => Array.from(
    { length: totalQuestions },
    (_, i) => ({ slug, questionNumber: String(i + 1) }),
  ));
}

export default async function PrayerPage(
  { params }: { params: Promise<{ slug: string; questionNumber: string }> },
) {
  const { slug, questionNumber } = await params;
  const program = getProgram(slug);
  const n = Number(questionNumber);
  if (!program || !Number.isInteger(n) || !getQuestion(program, n)) notFound();
  return (
    <Suspense fallback={<div className="min-h-64" aria-hidden="true" />}>
      <PrayerClient program={program} questionNumber={n} totalQuestions={program.totalQuestions} />
    </Suspense>
  );
}
