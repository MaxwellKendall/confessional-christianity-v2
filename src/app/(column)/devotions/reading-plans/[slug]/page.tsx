import type { Metadata } from 'next';
import { notFound } from 'next/navigation';

import { getReadingPlan, READING_PLANS } from '@/lib/readingPlans';
import { ReadingPlanClient } from './ReadingPlanClient';

interface Params {
  slug: string;
}

export const dynamicParams = false;

export function generateStaticParams(): Params[] {
  return READING_PLANS.map(({ slug }) => ({ slug }));
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { slug } = await params;
  const plan = getReadingPlan(slug);
  if (!plan) return {};
  return { title: plan.title, description: plan.description };
}

export default async function ReadingPlanPage({ params }: { params: Promise<Params> }) {
  const { slug } = await params;
  const plan = getReadingPlan(slug);
  if (!plan) notFound();
  return <ReadingPlanClient plan={plan} />;
}
