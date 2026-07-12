import { describe, expect } from 'vitest';

import {
  applyReviewMark,
  buildSessionPlan,
  defaultPacingForAge,
  masteryStateFor,
  type PacingConfig,
} from '@/lib/programs';
import type { QuestionMasteryRow } from '@/lib/database.types';
import { defineCases } from './support/defineCases';

const masteryRow = (
  questionNumber: number,
  partial: Partial<QuestionMasteryRow> = {},
): QuestionMasteryRow => ({
  id: `m-${questionNumber}`,
  assignment_id: 'a-1',
  question_number: questionNumber,
  state: 'reviewing',
  recited_streak: 0,
  exposures: 0,
  last_reviewed_at: null,
  created_at: '',
  updated_at: '',
  ...partial,
});

const pacing = (partial: Partial<PacingConfig> = {}): PacingConfig => ({
  ...defaultPacingForAge(9),
  ...partial,
});

describe('session planning', () => {
  const cases = {
    'introduces the configured number of new questions from the current position': {
      actual: () => buildSessionPlan(7, 107, [], pacing({ newQuestionsPerSession: 2 })),
      expected: { newQuestions: [7, 8], reviewQuestions: [], isComplete: false },
    },
    'younger-child default introduces one new question': {
      actual: () => buildSessionPlan(7, 107, [], defaultPacingForAge(6)),
      expected: { newQuestions: [7], reviewQuestions: [], isComplete: false },
    },
    'never introduces past the end of the catechism': {
      actual: () => buildSessionPlan(107, 107, [], pacing({ newQuestionsPerSession: 3 })),
      expected: { newQuestions: [107], reviewQuestions: [], isComplete: false },
    },
    'a position past the end is the completed state (PRD 5.7)': {
      actual: () => buildSessionPlan(108, 107, [], pacing()),
      expected: { newQuestions: [], reviewQuestions: [], isComplete: true },
    },
    'weak-only review skips mastered questions': {
      actual: () => buildSessionPlan(
        7,
        107,
        [
          masteryRow(1, { state: 'mastered' }),
          masteryRow(4, { state: 'reviewing' }),
        ],
        pacing({ reviewDepth: 'weak_only', newQuestionsPerSession: 1 }),
      ).reviewQuestions,
      expected: [4],
    },
    'recent review keeps only the last five learned': {
      actual: () => buildSessionPlan(
        9,
        107,
        [1, 2, 3, 4, 5, 6, 7, 8].map((n) => masteryRow(n)),
        pacing({ reviewDepth: 'recent', newQuestionsPerSession: 1 }),
      ).reviewQuestions,
      expected: [4, 5, 6, 7],
    },
    'rotation review picks the least recently reviewed first': {
      actual: () => buildSessionPlan(
        7,
        107,
        [
          masteryRow(1, { last_reviewed_at: '2026-07-09' }),
          masteryRow(4, { last_reviewed_at: '2026-07-01' }),
          masteryRow(6, { last_reviewed_at: '2026-07-05' }),
        ],
        pacing({ reviewDepth: 'rotation', newQuestionsPerSession: 1 }),
      ).reviewQuestions,
      expected: [4, 6, 1],
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
    'a third straight recitation masters under the streak rule': {
      actual: () => applyReviewMark(
        { state: 'reviewing', recited_streak: 2, exposures: 4 },
        true,
        'streak',
      ),
      expected: { state: 'mastered', recited_streak: 3, exposures: 5 },
    },
    'needing practice resets the streak without demoting mastery': {
      actual: () => applyReviewMark(
        { state: 'mastered', recited_streak: 3, exposures: 6 },
        false,
        'streak',
      ),
      expected: { state: 'mastered', recited_streak: 0, exposures: 7 },
    },
    'the exposures rule masters at six exposures regardless of recitation': {
      actual: () => applyReviewMark(
        { state: 'reviewing', recited_streak: 0, exposures: 5 },
        false,
        'exposures',
      ),
      expected: { state: 'mastered', recited_streak: 0, exposures: 6 },
    },
    'the manual rule never auto-masters': {
      actual: () => applyReviewMark(
        { state: 'reviewing', recited_streak: 9, exposures: 20 },
        true,
        'manual',
      ),
      expected: { state: 'reviewing', recited_streak: 10, exposures: 21 },
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
