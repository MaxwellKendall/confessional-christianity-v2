// The reading-plans domain (turn 19): a second program type, sibling to
// catechisms. A plan is a fixed-length walk through the whole Bible in
// canonical order — no external plan data to source, the canon itself is
// the plan (see readingPlanContent.ts for the day-by-day schedule).
export interface ReadingPlanDefinition {
  slug: string;
  title: string;
  /** conversational short name used in CTAs ("Continue {shortTitle}") */
  shortTitle: string;
  /** eyebrow shown on the picker (turn 19b): the plan's pace */
  pace: string;
  description: string;
  totalDays: number;
}

export const READING_PLANS: ReadingPlanDefinition[] = [
  {
    slug: 'whole-bible-one-year',
    title: 'Whole Bible, One Year',
    shortTitle: 'One Year',
    pace: 'One Year',
    description: 'The whole Bible, canonical order, in daily readings across a year.',
    totalDays: 365,
  },
  {
    slug: 'bible-in-90-days',
    title: 'The Bible in 90 Days',
    shortTitle: '90 Days',
    pace: '90-Day',
    description: 'The whole Bible, canonical order, at a faster daily pace.',
    totalDays: 90,
  },
];

export const getReadingPlan = (slug: string): ReadingPlanDefinition | null => READING_PLANS
  .find((p) => p.slug === slug) ?? null;
