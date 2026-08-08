// Reading plan day-by-day schedule (turn 19, adapted for the devotions
// hub): a plan's days aren't authored content — they're the canon itself,
// walked in canonical order and split evenly across the plan's length.
// BIBLE_BOOKS already holds that order and each book's chapter count (see
// bible.ts), so a day's reading is derived, never stored.
import { BIBLE_BOOKS } from './bible';
import type { ReadingPlanDefinition } from './readingPlans';

export interface ReadingPlanDay {
  day: number;
  /** OSIS chapter range ("Gen.34-Gen.36"), the citation/text fetch key. */
  osis: string;
  /** display citation ("Genesis 34–36"). */
  citation: string;
}

interface Chapter {
  bookOsis: string;
  bookName: string;
  chapter: number;
}

const ALL_CHAPTERS: Chapter[] = BIBLE_BOOKS.flatMap((book) => (
  Array.from({ length: book.chapters }, (_, i) => ({
    bookOsis: book.osis, bookName: book.name, chapter: i + 1,
  }))
));

const citationFor = (chapters: Chapter[]): string => {
  const first = chapters[0];
  const last = chapters[chapters.length - 1];
  if (first.bookOsis === last.bookOsis) {
    return first.chapter === last.chapter
      ? `${first.bookName} ${first.chapter}`
      : `${first.bookName} ${first.chapter}–${last.chapter}`;
  }
  return `${first.bookName} ${first.chapter} – ${last.bookName} ${last.chapter}`;
};

const osisFor = (chapters: Chapter[]): string => {
  const first = chapters[0];
  const last = chapters[chapters.length - 1];
  const start = `${first.bookOsis}.${first.chapter}`;
  const end = `${last.bookOsis}.${last.chapter}`;
  return start === end ? start : `${start}-${end}`;
};

/** One day's reading: the canon's chapters split evenly across the plan's
 * length, in canonical order. Null outside the plan's day range. */
export const getReadingPlanDay = (
  plan: ReadingPlanDefinition,
  day: number,
): ReadingPlanDay | null => {
  if (!Number.isInteger(day) || day < 1 || day > plan.totalDays) return null;
  const total = ALL_CHAPTERS.length;
  const start = Math.floor((total * (day - 1)) / plan.totalDays);
  const end = Math.floor((total * day) / plan.totalDays);
  const chapters = ALL_CHAPTERS.slice(start, end);
  if (chapters.length === 0) return null;
  return { day, osis: osisFor(chapters), citation: citationFor(chapters) };
};

/** The whole plan's schedule, in order — the calendar grid's day list reads
 * off this. */
export const getReadingPlanSchedule = (
  plan: ReadingPlanDefinition,
): ReadingPlanDay[] => Array.from(
  { length: plan.totalDays },
  (_, i) => getReadingPlanDay(plan, i + 1)!,
);
