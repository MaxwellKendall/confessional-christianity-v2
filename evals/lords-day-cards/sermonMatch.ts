import { normalizeForMatch, type SermonField } from '@/lib/lordsDay/cards';

// How the cards eval (and its offline check in test/lordsDaySermon.test.ts) scores
// the `sermon` object (TKL-1061). Truth for each field is null (the notes don't say
// it) or a string; text fields may list `|` alternatives, matched as substrings of
// the normalised value. passage and serviceDate must be equal.

const textMatch = (actual: string, expected: string) => {
  const value = normalizeForMatch(actual);
  return expected.split('|').some((alt) => value.includes(normalizeForMatch(alt)));
};

/** The value is what the truth says (both null counts). */
export const sermonFieldMatches = (field: SermonField, actual: string | null, expected: string | null): boolean => {
  if (expected === null || actual === null) return expected === actual;
  if (field === 'passage' || field === 'serviceDate') return actual === expected;
  return textMatch(actual, expected);
};

/**
 * Wrong, but plainly a reading of the right thing: the same book and chapter, the
 * same month and day (handwritten digits misread), or most of the same words.
 */
export const sermonFieldMisread = (field: SermonField, actual: string | null, expected: string | null): boolean => {
  if (actual === null || expected === null || sermonFieldMatches(field, actual, expected)) return false;
  if (field === 'passage') return actual.split(':')[0] === expected.split(':')[0];
  if (field === 'serviceDate') return actual.slice(5) === expected.slice(5);
  const words = new Set(normalizeForMatch(actual).split(' '));
  return expected.split('|').some((alt) => {
    const want = normalizeForMatch(alt).split(' ');
    return want.filter((w) => words.has(w)).length * 2 >= want.length;
  });
};

/**
 * A value the truth doesn't support and that isn't a misreading of it: made up.
 * A missing value is a miss, not this.
 */
export const sermonFieldMadeUp = (field: SermonField, actual: string | null, expected: string | null): boolean =>
  actual !== null && !sermonFieldMatches(field, actual, expected) && !sermonFieldMisread(field, actual, expected);
