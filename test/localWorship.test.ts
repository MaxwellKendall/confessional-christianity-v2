import { describe, expect } from 'vitest';

import { computeStreak, localDateKey, type WorshipCompletions } from '@/lib/localWorship';
import { defineCases } from './support/defineCases';

const TODAY = '2026-07-15';

describe('computeStreak', () => {
  const cases: Record<string, { completions: WorshipCompletions; expected: number }> = {
    'no completions yet — no streak': {
      completions: {},
      expected: 0,
    },
    'first service today starts the streak at one': {
      completions: { '2026-07-15': { morning: true } },
      expected: 1,
    },
    'one service a day sustains the streak': {
      completions: {
        '2026-07-13': { evening: true },
        '2026-07-14': { morning: true },
        '2026-07-15': { morning: true },
      },
      expected: 3,
    },
    'both dayparts in one day still count one day': {
      completions: {
        '2026-07-14': { morning: true, evening: true },
        '2026-07-15': { morning: true, evening: true },
      },
      expected: 2,
    },
    "today's service not yet held — yesterday's streak stands": {
      completions: {
        '2026-07-13': { morning: true },
        '2026-07-14': { evening: true },
      },
      expected: 2,
    },
    'a missed day breaks the streak': {
      completions: {
        '2026-07-12': { morning: true },
        '2026-07-13': { morning: true },
        '2026-07-15': { morning: true },
      },
      expected: 1,
    },
    'a lapsed streak from last week reads as zero': {
      completions: {
        '2026-07-08': { morning: true },
        '2026-07-09': { evening: true },
      },
      expected: 0,
    },
    'counts across a month boundary': {
      completions: {
        '2026-06-30': { evening: true },
        '2026-07-01': { morning: true },
      },
      expected: 2,
    },
  };

  defineCases(cases, ({ completions, expected }, name) => {
    const today = name === 'counts across a month boundary' ? '2026-07-01' : TODAY;
    expect(computeStreak(completions, today)).toBe(expected);
  });
});

describe('localDateKey', () => {
  const cases = {
    'formats a local date as YYYY-MM-DD': {
      actual: () => localDateKey(new Date(2026, 6, 15, 23, 59)),
      expected: '2026-07-15',
    },
    'pads single-digit months and days': {
      actual: () => localDateKey(new Date(2026, 0, 5)),
      expected: '2026-01-05',
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
