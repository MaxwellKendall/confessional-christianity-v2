import { describe, expect, test } from 'vitest';

import {
  dayIndexOf, getService, stepDetail, type Daypart,
} from '@/lib/worship';

const DAYPARTS: Daypart[] = ['morning', 'evening'];

describe('getService', () => {
  test('both dayparts follow the eight-step order of service', () => {
    DAYPARTS.forEach((daypart) => {
      const service = getService(daypart, new Date(2026, 6, 15));
      expect(service.steps.map((s) => s.role)).toEqual([
        'Call to Worship',
        'Confessing Sin',
        'Receiving Forgiveness',
        'Singing Praise',
        'Professing Faith',
        'Reading Scripture',
        'Making Requests',
        'Closing Prayer',
      ]);
    });
  });

  test('rotations resolve — no rotation elements reach the renderer', () => {
    DAYPARTS.forEach((daypart) => {
      const service = getService(daypart, new Date(2026, 6, 15));
      service.steps.forEach((step) => {
        expect(step.elements.length).toBeGreaterThan(0);
        step.elements.forEach((el) => expect(el.type).not.toBe('rotation'));
      });
    });
  });

  test('the same date always yields the same service', () => {
    const a = getService('morning', new Date(2026, 6, 15, 6, 30));
    const b = getService('morning', new Date(2026, 6, 15, 21, 45));
    expect(a).toEqual(b);
  });

  test('consecutive days rotate the call to worship', () => {
    const cited = (date: Date) => stepDetail(getService('morning', date).steps[0]);
    const days = [15, 16, 17].map((d) => cited(new Date(2026, 6, d)));
    expect(new Set(days).size).toBe(3);
  });

  test('professing faith is the catechism hand-off, fifth in the order', () => {
    DAYPARTS.forEach((daypart) => {
      const step = getService(daypart, new Date(2026, 6, 15)).steps[4];
      expect(step.role).toBe('Professing Faith');
      expect(step.elements[0].type).toBe('catechism');
    });
  });
});

describe('dayIndexOf', () => {
  test('ignores the time of day and steps by one per calendar day', () => {
    const morning = dayIndexOf(new Date(2026, 6, 15, 0, 1));
    const night = dayIndexOf(new Date(2026, 6, 15, 23, 59));
    const nextDay = dayIndexOf(new Date(2026, 6, 16, 0, 1));
    expect(morning).toBe(night);
    expect(nextDay).toBe(morning + 1);
  });
});

describe('stepDetail', () => {
  const service = getService('morning', new Date(2026, 6, 15));
  const details = service.steps.map(stepDetail);

  test('names the scripture or song a step opens with', () => {
    expect(details[0]).toMatch(/^Psalm/);
    expect(details[3]).toBeTruthy();
    expect(details[5]).toBeTruthy();
  });

  test('stays quiet for roles that stand alone', () => {
    expect(details[1]).toBeNull();
    expect(details[4]).toBeNull();
    expect(details[7]).toBeNull();
  });
});
