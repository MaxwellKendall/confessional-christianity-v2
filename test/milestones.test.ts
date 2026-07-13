import { describe, expect } from 'vitest';

import { milestoneProgress, milestonesFor, type MilestoneDefinition } from '@/lib/milestones';
import { defineCases } from './support/defineCases';

const def = (partial: Partial<MilestoneDefinition> = {}): MilestoneDefinition => ({
  id: 'm',
  title: 'A Milestone',
  range: [1, 10],
  ...partial,
});

describe('milestonesFor', () => {
  const cases = {
    'a program with authored milestones returns them': {
      actual: () => milestonesFor('catechizing-shorter-catechism').length > 0,
      expected: true,
    },
    'a program with none returns an empty list': {
      actual: () => milestonesFor('not-a-real-program'),
      expected: [],
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('milestoneProgress', () => {
  const cases = {
    'a position before the range is locked': {
      actual: () => milestoneProgress([def({ range: [1, 10] })], 1),
      expected: [{
        id: 'm', title: 'A Milestone', range: [1, 10], total: 10, seenCount: 0, state: 'locked',
      }],
    },
    'a position inside the range is in progress': {
      actual: () => milestoneProgress([def({ range: [1, 10] })], 5),
      expected: [{
        id: 'm', title: 'A Milestone', range: [1, 10], total: 10, seenCount: 4, state: 'in_progress',
      }],
    },
    'a position past the range is complete': {
      actual: () => milestoneProgress([def({ range: [1, 10] })], 11),
      expected: [{
        id: 'm', title: 'A Milestone', range: [1, 10], total: 10, seenCount: 10, state: 'complete',
      }],
    },
    'a range not starting at question 1 locks until reached': {
      actual: () => milestoneProgress([def({ range: [42, 81] })], 42),
      expected: [{
        id: 'm', title: 'A Milestone', range: [42, 81], total: 40, seenCount: 0, state: 'locked',
      }],
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
