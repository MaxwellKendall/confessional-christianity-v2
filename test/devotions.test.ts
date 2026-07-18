import { describe, expect, test } from 'vitest';

import { BIBLE_BOOKS } from '@/lib/bible';
import {
  SEASONS, TOPICS, devotionsGroundedIn, getAllDevotions, getDevotion,
  getFeaturedDevotion, groundingBookOsis, groundingChapter, groundingLabel,
  scriptureDevotionsByBook,
} from '@/lib/devotions';
import { getService, stepDetail } from '@/lib/worship';

describe('the devotion manifest', () => {
  test('every devotion is retrievable by its slug', () => {
    getAllDevotions().forEach((devotion) => {
      expect(getDevotion(devotion.slug)).toBe(devotion);
    });
  });

  test('unknown slugs return null', () => {
    expect(getDevotion('psalm-131')).toBeNull();
  });

  test('the featured pick is a real devotion', () => {
    expect(getAllDevotions()).toContain(getFeaturedDevotion());
  });

  test('slugs are unique', () => {
    const slugs = getAllDevotions().map((d) => d.slug);
    expect(new Set(slugs).size).toBe(slugs.length);
  });
});

describe('a devotion hands off to the eight-step worship shell', () => {
  // The worship service defines the shell's order of service; a devotion's
  // steps must be the same eight roles so the renderer needs no new cases.
  const serviceRoles = getService('morning', new Date(2026, 6, 15))
    .steps.map((s) => s.role);

  test('every devotion follows the same eight-step order as the service', () => {
    getAllDevotions().forEach((devotion) => {
      expect(devotion.steps.map((s) => s.role)).toEqual(serviceRoles);
    });
  });

  test('steps are pre-resolved — no rotation elements, none empty', () => {
    getAllDevotions().forEach((devotion) => {
      devotion.steps.forEach((step) => {
        expect(step.elements.length).toBeGreaterThan(0);
        step.elements.forEach((el) => expect(el.type).not.toBe('rotation'));
      });
    });
  });

  test('professing faith stays the catechism hand-off, fifth in the order', () => {
    getAllDevotions().forEach((devotion) => {
      const step = devotion.steps[4];
      expect(step.role).toBe('Professing Faith');
      expect(step.elements[0].type).toBe('catechism');
    });
  });

  test('stepDetail reads devotion steps like service steps (15c order preview)', () => {
    const devotion = getDevotion('psalm-130')!;
    expect(stepDetail(devotion.steps[0])).toBe('Psalm 130:1–2');
    expect(stepDetail(devotion.steps[1])).toBeNull();
  });
});

describe('grounding', () => {
  test('psalm-130 is grounded in the scripture axis', () => {
    const devotion = getDevotion('psalm-130')!;
    expect(devotion.grounding).toEqual({ kind: 'scripture', osis: 'Ps.130', citation: 'Psalm 130' });
    expect(devotionsGroundedIn('scripture')).toContain(devotion);
    expect(devotionsGroundedIn('topic')).not.toContain(devotion);
  });

  test('labels name what a devotion is grounded in, per axis', () => {
    expect(groundingLabel({ kind: 'scripture', osis: 'Ps.130', citation: 'Psalm 130' })).toBe('Psalm 130');
    expect(groundingLabel({ kind: 'topic', topic: 'repentance' })).toBe('Repentance');
    expect(groundingLabel({ kind: 'catechism', entryId: 'WSC-1' })).toBe('WSC Q. 1');
    expect(groundingLabel({ kind: 'season', season: 'advent', day: 3 })).toBe('Advent · Day 3');
  });

  test('labels degrade to the raw value when a registry lookup misses', () => {
    expect(groundingLabel({ kind: 'topic', topic: 'lament' })).toBe('lament');
    expect(groundingLabel({ kind: 'catechism', entryId: 'XYZ-9' })).toBe('XYZ-9');
  });
});

describe('the scripture browse (15b)', () => {
  test('a grounding names its book and starting chapter', () => {
    const grounding = getDevotion('psalm-130')!.grounding;
    expect(groundingBookOsis(grounding)).toBe('Ps');
    expect(groundingChapter(grounding)).toBe(130);
    expect(groundingBookOsis({ kind: 'topic', topic: 'gratitude' })).toBeNull();
    expect(groundingChapter({ kind: 'topic', topic: 'gratitude' })).toBeNull();
  });

  test('devotions group under their OSIS book, in chapter order', () => {
    const byBook = scriptureDevotionsByBook();
    expect(byBook.get('Ps')).toEqual([getDevotion('psalm-130')]);
    for (const [book, devotions] of byBook) {
      expect(BIBLE_BOOKS.some((b) => b.osis === book)).toBe(true);
      const chapters = devotions.map((d) => groundingChapter(d.grounding) ?? 0);
      expect(chapters).toEqual([...chapters].sort((a, b) => a - b));
    }
  });

  test('the canon table holds all 66 books and 1,189 chapters, named', () => {
    expect(BIBLE_BOOKS).toHaveLength(66);
    expect(BIBLE_BOOKS.filter((b) => b.testament === 'old')).toHaveLength(39);
    expect(BIBLE_BOOKS.reduce((sum, b) => sum + b.chapters, 0)).toBe(1189);
    BIBLE_BOOKS.forEach((b) => expect(b.name, b.osis).toBeTruthy());
    expect(BIBLE_BOOKS[0].name).toBe('Genesis');
    expect(BIBLE_BOOKS[65].name).toBe('Revelation');
  });
});

describe('the browse registries', () => {
  test('topics carry the hub row\'s curated vocabulary', () => {
    expect(TOPICS.map((t) => t.slug)).toEqual(
      ['repentance', 'gratitude', 'suffering', 'anxiety', 'vocation'],
    );
  });

  test('seasons size their daily runs (Advent 24, Lent 40)', () => {
    expect(SEASONS.map((s) => [s.slug, s.days])).toEqual([['advent', 24], ['lent', 40]]);
  });
});
