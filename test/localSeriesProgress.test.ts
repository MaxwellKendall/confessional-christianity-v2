import { describe, expect } from 'vitest';

import { currentPartDay } from '@/lib/localSeriesProgress';
import { defineCases } from './support/defineCases';

describe('currentPartDay', () => {
  const cases: Record<string, { completed: number[]; totalParts: number; expected: number | null }> = {
    'a fresh household starts at part 1': {
      completed: [],
      totalParts: 24,
      expected: 1,
    },
    'finishing part 1 unlocks part 2': {
      completed: [1],
      totalParts: 24,
      expected: 2,
    },
    'progress resumes exactly where the household left off (16a: part 9 of 24)': {
      completed: [1, 2, 3, 4, 5, 6, 7, 8],
      totalParts: 24,
      expected: 9,
    },
    'the first gap is current, even past later completions': {
      completed: [1, 3],
      totalParts: 24,
      expected: 2,
    },
    'completion order in the store does not matter': {
      completed: [2, 1],
      totalParts: 24,
      expected: 3,
    },
    'a finished series has no current part': {
      completed: [1, 2, 3],
      totalParts: 3,
      expected: null,
    },
  };

  defineCases(cases, ({ completed, totalParts, expected }) => {
    expect(currentPartDay(completed, totalParts)).toBe(expected);
  });
});
