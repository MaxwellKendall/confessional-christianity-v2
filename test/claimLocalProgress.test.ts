import { describe, expect } from 'vitest';

import { buildClaimRows } from '@/lib/claimLocalProgress';
import type { LocalCatechismTrack } from '@/lib/localCatechismProgress';
import { defineCases } from './support/defineCases';

const T0 = '2026-07-01T00:00:00.000Z';
const T1 = '2026-07-05T00:00:00.000Z';

const track = (partial: Partial<LocalCatechismTrack> = {}): LocalCatechismTrack => ({
  catechismId: 'WSC',
  currentQuestion: 3,
  startedAtQuestion: 1,
  startedAt: T0,
  updatedAt: T1,
  milestones: {},
  ...partial,
});

describe('buildClaimRows (guest → account migration)', () => {
  const cases = {
    'assignment lands at the local position': {
      actual: () => buildClaimRows(track(), 7).assignment,
      expected: { catechism_id: 'WSC', current_question: 3 },
    },
    'pacing seeds from an under-8 age': {
      actual: () => buildClaimRows(track(), 6).pacing,
      expected: {
        new_questions_per_session: 1,
        sessions_per_week: 3,
        review_depth: 'rotation',
        mastery_rule: 'streak',
        show_scripture_every_time: true,
      },
    },
    'pacing seeds from an 8-or-older age': {
      actual: () => buildClaimRows(track(), 9).pacing.new_questions_per_session,
      expected: 2,
    },
    'pacing seeds sanely with no age given': {
      actual: () => buildClaimRows(track(), null).pacing.new_questions_per_session,
      expected: 2,
    },
    'introduced and reviewing milestones enter rotation; mastered carries over': {
      actual: () => buildClaimRows(track({
        milestones: {
          2: { state: 'reviewing', introducedAt: T0, reviewCount: 2 },
          1: { state: 'mastered', introducedAt: T0, reviewCount: 4 },
          3: { state: 'introduced', introducedAt: T1, reviewCount: 0 },
        },
      }), 9).mastery,
      expected: [
        {
          question_number: 1, state: 'mastered', recited_streak: 0, exposures: 5, last_reviewed_at: T0,
        },
        {
          question_number: 2, state: 'reviewing', recited_streak: 0, exposures: 3, last_reviewed_at: T0,
        },
        {
          question_number: 3, state: 'reviewing', recited_streak: 0, exposures: 1, last_reviewed_at: T1,
        },
      ],
    },
    'a track with no milestones claims no mastery rows': {
      actual: () => buildClaimRows(track(), 9).mastery,
      expected: [],
    },
  };
  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
