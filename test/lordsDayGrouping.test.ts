import { readFileSync } from 'fs';
import path from 'path';
import { describe, expect, test } from 'vitest';

import { proposeGroups, scoreGrouping, type GroupingPage } from '@/lib/lordsDay/grouping';
import type { SermonDetails } from '@/lib/lordsDay/cards';

// TKL-1107: batch import groups pages into sermons from each page's `sermon` event
// and photo time. The app's rule is DomainKit's SermonGrouping; this port scores the
// eval offline (no model call) from the recorded page events in grouping.json.

const blank: SermonDetails = { title: null, preacher: null, passage: null, church: null, serviceDate: null };
const page = (s: Partial<SermonDetails> = {}, takenAt: string | null = null): GroupingPage => ({
  takenAt,
  sermon: { ...blank, ...s },
});

describe('proposeGroups', () => {
  test('a heading change starts a new sermon; a page naming nothing continues it', () => {
    expect(proposeGroups([page({ title: 'Gospel Partnership' }), page(), page({ title: 'A Tale of Two Prayers' })])).toEqual([[0, 1], [2]]);
  });
  test('a date or passage change starts a new sermon', () => {
    expect(proposeGroups([page({ serviceDate: '2020-09-06' }), page({ serviceDate: '2020-09-20' })])).toEqual([[0], [1]]);
    expect(proposeGroups([page({ passage: 'Psalms 1' }), page({ passage: 'Malachi 1:2-5' })])).toEqual([[0], [1]]);
  });
  test('the same title in another case or punctuation continues it', () => {
    expect(proposeGroups([page({ title: 'Benediction' }), page({ title: 'benediction.' })])).toEqual([[0, 1]]);
  });
  test('a photo gap over 6 hours starts a new sermon', () => {
    expect(proposeGroups([page({}, '2026-11-01T17:00:00Z'), page({}, '2026-11-01T22:00:00Z'), page({}, '2026-11-08T17:00:00Z')])).toEqual([[0, 1], [2]]);
  });
});

describe('scoreGrouping', () => {
  test('scores each boundary between neighbouring pages', () => {
    expect(scoreGrouping([[0, 1], [2]], [[0, 1], [2]])).toEqual({ correct: 2, total: 2, pass: true });
    expect(scoreGrouping([[0, 1, 2]], [[0, 1], [2]])).toEqual({ correct: 1, total: 2, pass: false });
  });
});

interface GroupingEval {
  gapHours: number;
  recorded: Record<string, SermonDetails>;
  batches: { id: string; pages: { case: string; takenAt: string | null }[]; truth: number[][] }[];
}

test('grouping eval: every batch groups as its truth from the recorded page events', () => {
  const evalFile = path.join(__dirname, '..', 'evals', 'lords-day-cards', 'grouping.json');
  const { gapHours, recorded, batches } = JSON.parse(readFileSync(evalFile, 'utf8')) as GroupingEval;
  const truth = JSON.parse(readFileSync(path.join(__dirname, '..', 'evals', 'lords-day-cards', 'truth.json'), 'utf8')) as {
    cases: { id: string; photo?: string }[];
  };
  expect(batches.length).toBeGreaterThanOrEqual(3);
  for (const batch of batches) {
    for (const p of batch.pages) {
      expect(recorded[p.case], `${batch.id}: ${p.case} has a recorded read`).toBeDefined();
      expect(truth.cases.find((c) => c.id === p.case)?.photo, `${p.case} is a golden photo`).toBeTruthy();
    }
    const groups = proposeGroups(batch.pages.map((p) => ({ takenAt: p.takenAt, sermon: recorded[p.case] })), gapHours);
    expect(scoreGrouping(groups, batch.truth), batch.id).toMatchObject({ pass: true });
  }
});
