import { describe, expect } from 'vitest';

import { getProgram, masteryStateFor, PROGRAMS } from '@/lib/programs';
import { defineCases } from './support/defineCases';

describe('getProgram', () => {
  const cases = {
    'finds a registered program by slug': {
      actual: () => getProgram(PROGRAMS[0].slug)?.slug,
      expected: PROGRAMS[0].slug,
    },
    'returns null for an unknown slug': {
      actual: () => getProgram('not-a-real-program'),
      expected: null,
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('mastery rules', () => {
  const cases = {
    'absence of a row means not started': {
      actual: () => masteryStateFor(undefined),
      expected: 'not_started',
    },
    'a row carries its own state through': {
      actual: () => masteryStateFor({ state: 'mastered' }),
      expected: 'mastered',
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
