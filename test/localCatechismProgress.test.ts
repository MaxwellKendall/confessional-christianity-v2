import { describe, expect } from 'vitest';

import {
  advanceTrack,
  migrateStoredShape,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { defineCases } from './support/defineCases';

const track = (partial: Partial<LocalCatechismTrack> = {}): LocalCatechismTrack => ({
  catechismId: 'WSC',
  currentQuestion: 1,
  startedAtQuestion: 1,
  startedAt: '2026-07-01T00:00:00.000Z',
  updatedAt: '2026-07-01T00:00:00.000Z',
  milestones: {},
  ...partial,
});

const NOW = '2026-07-11T00:00:00.000Z';

describe('advanceTrack (7c "Next Question")', () => {
  const cases = {
    'introduces the current question and moves to the next': {
      actual: () => advanceTrack(track(), 107, NOW),
      expected: track({
        currentQuestion: 2,
        updatedAt: NOW,
        milestones: { 1: { state: 'introduced', introducedAt: NOW, reviewCount: 0 } },
      }),
    },
    'leaves an already-recorded milestone untouched': {
      actual: () => advanceTrack(track({
        currentQuestion: 1,
        milestones: { 1: { state: 'mastered', introducedAt: '2026-07-02T00:00:00.000Z', reviewCount: 3 } },
      }), 107, NOW),
      expected: track({
        currentQuestion: 2,
        updatedAt: NOW,
        milestones: { 1: { state: 'mastered', introducedAt: '2026-07-02T00:00:00.000Z', reviewCount: 3 } },
      }),
    },
    'clamps one past the end so a finished track reads as complete': {
      actual: () => advanceTrack(track({ currentQuestion: 107 }), 107, NOW),
      expected: track({
        currentQuestion: 108,
        updatedAt: NOW,
        milestones: { 107: { state: 'introduced', introducedAt: NOW, reviewCount: 0 } },
      }),
    },
    'does not advance or record past the completed position': {
      actual: () => advanceTrack(track({ currentQuestion: 108 }), 107, NOW),
      expected: track({ currentQuestion: 108, updatedAt: NOW, milestones: {} }),
    },
  };
  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('migrateStoredShape', () => {
  const v1Track = track({ currentQuestion: 3 });
  const cases = {
    'carries a v1 store forward, dropping any learner fields': {
      actual: () => migrateStoredShape({
        version: 1,
        activeCatechismId: 'WSC',
        learnerName: 'Eli',
        tracks: { WSC: v1Track },
      }),
      expected: {
        version: 2,
        activeCatechismId: 'WSC',
        tracks: { WSC: v1Track },
      },
    },
    'passes a v2 store through, dropping any learner fields': {
      actual: () => migrateStoredShape({
        version: 2,
        activeCatechismId: 'WSC',
        learnerName: 'Eli',
        learnerAge: 7,
        tracks: { WSC: v1Track },
      }),
      expected: {
        version: 2,
        activeCatechismId: 'WSC',
        tracks: { WSC: v1Track },
      },
    },
    'rejects an unknown version': {
      actual: () => migrateStoredShape({ version: 3, tracks: {} }),
      expected: null,
    },
    'rejects non-object payloads': {
      actual: () => migrateStoredShape('not json we wrote'),
      expected: null,
    },
    'fills defaults for a sparse v1 store': {
      actual: () => migrateStoredShape({ version: 1 }),
      expected: {
        version: 2,
        activeCatechismId: null,
        tracks: {},
      },
    },
  };
  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
