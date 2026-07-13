import { describe, expect } from 'vitest';

import { getProgram, PROGRAMS } from '@/lib/programs';
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
