import { describe, expect } from 'vitest';

import { getQuestion, getQuestionCitations, getPrayer, hasPrayer } from '@/lib/programContent';
import { getProgram } from '@/lib/programs';
import { defineCases } from './support/defineCases';

const wsc = getProgram('catechizing-shorter-catechism')!;
const cfyc = getProgram('catechism-for-young-children')!;
const wlc = getProgram('catechizing-larger-catechism')!;
const hc = getProgram('catechizing-heidelberg-catechism')!;

describe('program content', () => {
  const cases = {
    'WSC questions resolve with clean question and answer text': {
      actual: () => getQuestion(wsc, 7),
      assert: (q: ReturnType<typeof getQuestion>) => {
        expect(q?.question).toBe('What are the decrees of God?');
        expect(q?.answer).toContain('his eternal purpose');
        expect(q?.answer).not.toContain('[a]');
        expect(q?.proofTexts).toContain('Eph.1.4');
      },
    },
    'WSC citations group proof texts by clause': {
      actual: () => getQuestionCitations(wsc, 1),
      assert: (c: ReturnType<typeof getQuestionCitations>) => {
        expect(c?.groups.length).toBeGreaterThan(0);
        expect(c?.answerSegments.some((s) => s.marker)).toBe(true);
      },
    },
    'CfYC questions resolve from their own document': {
      actual: () => getQuestion(cfyc, 1),
      assert: (q: ReturnType<typeof getQuestion>) => {
        expect(q?.question).toBe('Who made you?');
        expect(q?.answer).toBe('God.');
      },
    },
    'CfYC has no proof texts, so citations render an empty group list': {
      actual: () => getQuestionCitations(cfyc, 1),
      assert: (c: ReturnType<typeof getQuestionCitations>) => {
        expect(c?.groups).toEqual([]);
        expect(c?.answerSegments.length).toBeGreaterThan(0);
      },
    },
    'prayers substitute the child name': {
      actual: () => getPrayer(wsc, 7, 'Eli'),
      assert: (prayer: string | null) => {
        expect(prayer).toContain('Help Eli trust');
      },
    },
    'unwritten prayers are honestly absent': {
      actual: () => ({ has: hasPrayer(wsc, 99), prayer: getPrayer(wsc, 99, 'Eli') }),
      assert: (result: { has: boolean; prayer: string | null }) => {
        expect(result).toEqual({ has: false, prayer: null });
      },
    },
    'a program with no authored prayers yet is honestly absent': {
      actual: () => ({ has: hasPrayer(cfyc, 1), prayer: getPrayer(cfyc, 1, 'Eli') }),
      assert: (result: { has: boolean; prayer: string | null }) => {
        expect(result).toEqual({ has: false, prayer: null });
      },
    },
    'WLC questions resolve, including the last one': {
      actual: () => [getQuestion(wlc, 1), getQuestion(wlc, 196)],
      assert: ([first, last]: (ReturnType<typeof getQuestion>)[]) => {
        expect(first?.question).toBe('What is the chief and highest end of man?');
        expect(last).not.toBeNull();
      },
    },
    // The Heidelberg's underlying entry.number is a raw content-array
    // position (Lord's Day headers share the sequence with questions), not
    // the traditional Q number — Question 1's entry.number is actually 2.
    // findEntry has to resolve by the title's stated number instead.
    'HC questions resolve by their stated number, not entry.number': {
      actual: () => getQuestion(hc, 1),
      assert: (q: ReturnType<typeof getQuestion>) => {
        expect(q?.question).toBe('What is thy only comfort in life and death?');
        expect(q?.answer).toContain('not my own');
      },
    },
    'HC resolves every question 1..129 with no gaps': {
      actual: () => Array.from({ length: 129 }, (_, i) => getQuestion(hc, i + 1)),
      assert: (questions: (ReturnType<typeof getQuestion>)[]) => {
        expect(questions.every((q) => q !== null)).toBe(true);
      },
    },
  };

  defineCases(cases, ({ actual, assert }) => {
    assert(actual() as never);
  });
});
