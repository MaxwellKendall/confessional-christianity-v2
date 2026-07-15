import { describe, expect, test } from 'vitest';

import { loadReflections } from '@/lib/reflections';
import { isResourceKind, RESOURCE_KIND_LABELS, RESOURCE_KINDS } from '@/lib/resourceKinds';
import { hasResources, loadResources } from '@/lib/resources';
import { defineCases } from './support/defineCases';

describe('loadResources', () => {
  test('returns the WSC-1 seeds in authored order, one of each kind', async () => {
    const resources = await loadResources('WSC-1');
    expect(resources.map((r) => r.kind)).toEqual(['song', 'podcast', 'book', 'essay', 'original']);
    expect(resources.map((r) => r.order)).toEqual([1, 2, 3, 4, 5]);
  });

  test('external kinds carry a url and no reflection; original the reverse', async () => {
    const resources = await loadResources('WSC-1');
    resources.forEach((r) => {
      if (r.kind === 'original') {
        expect(r.reflectionSlug).toBeTruthy();
        expect(r.url).toBeNull();
      } else {
        expect(r.url).toMatch(/^https:\/\//);
        expect(r.reflectionSlug).toBeNull();
      }
    });
  });

  test('every original resource points at a reflection that exists', async () => {
    const [resources, reflections] = await Promise.all([
      loadResources('WSC-1'),
      loadReflections(),
    ]);
    const reflectionSlugs = new Set(reflections.map((r) => r.slug));
    resources
      .filter((r) => r.kind === 'original')
      .forEach((r) => expect(reflectionSlugs.has(r.reflectionSlug!)).toBe(true));
  });

  test('an entry with no curated resources loads as empty, not an error', async () => {
    expect(await loadResources('WSC-2')).toEqual([]);
    expect(await hasResources('WSC-2')).toBe(false);
    expect(await hasResources('WSC-1')).toBe(true);
  });
});

describe('resource kinds', () => {
  const cases = {
    'every kind has chip and row labels': {
      actual: () => RESOURCE_KINDS.every((k) => (
        Boolean(RESOURCE_KIND_LABELS[k].chip) && Boolean(RESOURCE_KIND_LABELS[k].row)
      )),
      expected: true,
    },
    'recognizes a taxonomy kind': {
      actual: () => isResourceKind('podcast'),
      expected: true,
    },
    'rejects a kind outside the taxonomy': {
      actual: () => isResourceKind('sermon'),
      expected: false,
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
