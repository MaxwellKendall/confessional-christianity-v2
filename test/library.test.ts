// v2 replacement for v1's content-routes test: the route logic that lived in
// getStaticProps/getStaticPaths now lives in src/lib/library.ts, so the same
// behaviors are pinned there directly.
import { describe, expect } from 'vitest';

import { loadConfessionContent } from '@/lib/confessionContent';
import {
  getAllEntryParams,
  getDocumentDescription,
  getEntryPage,
} from '@/lib/library';
import { defineCases } from './support/defineCases';

interface AsyncCase {
  actual: () => Promise<unknown>;
  assert: (result: never) => void;
}

describe('loadConfessionContent', () => {
  const cases: Record<string, AsyncCase> = {
    'known slugs return normalized content keyed by id': {
      actual: async () => loadConfessionContent('westminster-confession-of-faith'),
      assert: (result: Awaited<ReturnType<typeof loadConfessionContent>>) => {
        expect(result?.documentId).toBe('WCoF');
        expect(result?.contentById['WCoF-1']).toMatchObject({
          id: 'WCoF-1',
          isParent: true,
        });
        expect(result?.contentById['WCoF-1-1']).toMatchObject({
          id: 'WCoF-1-1',
          parent: 'WCoF-1',
        });
      },
    },
    'unknown slugs return null': {
      actual: async () => loadConfessionContent('not-a-real-confession'),
      assert: (result: unknown) => {
        expect(result).toBeNull();
      },
    },
  };

  defineCases(cases, async ({ actual, assert }) => {
    assert((await actual()) as never);
  });
});

describe('library entry pages', () => {
  const cases: Record<string, AsyncCase> = {
    'entry pages return the leaf entry and adjacent links': {
      actual: async () => getEntryPage('westminster-confession-of-faith', '1-2'),
      assert: (page: Awaited<ReturnType<typeof getEntryPage>>) => {
        expect(page?.item.id).toBe('WCoF-1-2');
        expect(page?.documentTitle).toBe('Westminster Confession of Faith');
        expect(page?.prevEntry).toEqual({
          href: '/library/westminster-confession-of-faith/1-1',
          title: 'Article 1',
        });
        expect(page?.nextEntry).toEqual({
          href: '/library/westminster-confession-of-faith/1-3',
          title: 'Article 3',
        });
      },
    },
    'invalid entry segments return null': {
      actual: async () => getEntryPage('westminster-confession-of-faith', '999'),
      assert: (page: unknown) => {
        expect(page).toBeNull();
      },
    },
    'parent (chapter) ids do not get entry pages': {
      actual: async () => getEntryPage('westminster-confession-of-faith', '1'),
      assert: (page: unknown) => {
        expect(page).toBeNull();
      },
    },
    'entry params include both standard and canons entry formats': {
      actual: async () => getAllEntryParams(),
      assert: (params: Awaited<ReturnType<typeof getAllEntryParams>>) => {
        expect(params).toEqual(expect.arrayContaining([
          { confession: 'westminster-confession-of-faith', entry: '1-1' },
          { confession: 'canons-of-dort', entry: '1-articles-1' },
        ]));
      },
    },
    'document descriptions come from the opening entry text': {
      actual: async () => getDocumentDescription('westminster-confession-of-faith'),
      assert: (description: string) => {
        expect(description).toContain('Although the light of nature');
      },
    },
  };

  defineCases(cases, async ({ actual, assert }) => {
    assert((await actual()) as never);
  });
});
