import { describe, expect } from 'vitest';

import {
  compareEntryIds,
  entryIdToPathSegment,
  generateCanonicalEntryLink,
  generateNavLink,
  generateSearchLink,
  groupContentByChapter,
  isChapter,
  parseFacets,
  truncateForMeta,
} from '@/lib/helpers';
import { getPageTitle } from '@/lib/pageTitle';
import type { ConfessionEntry, ContentById } from '@/lib/domain';
import { defineCases } from './support/defineCases';

const entry = (partial: Partial<ConfessionEntry> & { id: string }): ConfessionEntry => ({
  parent: '',
  title: '',
  isParent: false,
  ...partial,
});

describe('parseFacets', () => {
  const cases = {
    'whole confession search resolves to the first chapter': {
      input: 'WCF',
      expected: ['parent:WCoF-1'],
    },
    'catechism search resolves to the first question': {
      input: 'WSC',
      expected: ['id:WSC-1'],
    },
    'chapter and article search resolves to a single entry id': {
      input: 'WCF.1.2',
      expected: ['id:WCoF-1-2'],
    },
    'canons rejection search resolves to the rejection entry id': {
      input: 'CD.1.r2',
      expected: ['id:CoD-1-rejections-2'],
    },
    'keyword bundle search expands to the westminster document facets': {
      input: 'westminster standards',
      expected: [[
        'document:Westminster Shorter Catechism',
        'document:Westminster Larger Catechism',
        'document:Westminster Confession of Faith',
      ]],
    },
    'bible range search resolves to book and citation facets': {
      input: 'John 3:16-17',
      expected: [
        'book:John',
        'startChapter:3',
        'startVerse:16',
        'endVerse:17',
      ],
    },
  };

  defineCases(cases, ({ input, expected }) => {
    expect(parseFacets(input)).toEqual(expected);
  });
});

describe('link generation', () => {
  const cases = {
    'search links use the v2 /search?q= route format': {
      actual: () => generateSearchLink('WCoF-1-2'),
      expected: '/search?q=WCF.1.2',
    },
    'canonical entry links use the single-segment library format': {
      actual: () => generateCanonicalEntryLink('CoD-1-articles-3'),
      expected: '/library/canons-of-dort/1-articles-3',
    },
    'nav links prefer canonical entry pages for leaf content': {
      actual: () => generateNavLink('WCoF-1-2', {
        'WCoF-1-2': entry({ id: 'WCoF-1-2', isParent: false }),
      } as ContentById),
      expected: '/library/westminster-confession-of-faith/1-2',
    },
    'nav links fall back to search routes for chapter-level targets': {
      actual: () => generateNavLink('WCoF-1', {
        'WCoF-1': entry({ id: 'WCoF-1', isParent: true }),
      } as ContentById),
      expected: '/search?q=WCF.1',
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('metadata helpers', () => {
  const cases = {
    'truncateForMeta removes footnote markers without truncating short text': {
      actual: () => truncateForMeta('Grace[a] and peace[b] be with you.'),
      expected: 'Grace and peace be with you.',
    },
    'truncateForMeta shortens long text at a word boundary': {
      actual: () => truncateForMeta('One two three four five six seven eight nine ten', 18),
      expected: 'One two three…',
    },
    'getPageTitle returns the default landing-page title copy': {
      actual: () => getPageTitle(),
      expected: ['Search the Confessions of Historic Protestantism', 'By Keyword, Scripture Text, or Citation'],
    },
    'getPageTitle resolves keyword bundle titles': {
      actual: () => getPageTitle('three forms of unity'),
      expected: ['The Three Forms Of Unity', null],
    },
    'getPageTitle resolves bible titles consistently across repeated calls': {
      actual: () => [getPageTitle('john 3:16'), getPageTitle('john 3:16')],
      expected: [
        ['John 3:16', null],
        ['John 3:16', null],
      ],
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('content structure helpers', () => {
  const cases = {
    'compareEntryIds sorts numeric and textual fragments in document order': {
      actual: () => ['CoD-1-rejections-2', 'CoD-1-articles-3', 'CoD-1-articles-1'].sort(compareEntryIds),
      expected: ['CoD-1-articles-1', 'CoD-1-articles-3', 'CoD-1-rejections-2'],
    },
    'entryIdToPathSegment strips the document prefix': {
      actual: () => entryIdToPathSegment('CoD-1-articles-3', 'CoD'),
      expected: '1-articles-3',
    },
    'groupContentByChapter normalizes canons article parents back to the chapter id': {
      actual: () => Object.keys(groupContentByChapter([
        entry({ id: 'CoD-1-articles-1', parent: 'CoD-1-articles' }),
        entry({ id: 'WCoF-1-1', parent: 'WCoF-1' }),
      ])).sort(),
      expected: ['CoD-1', 'WCoF-1'],
    },
    'isChapter only returns true for parent chapter entries': {
      actual: () => ({
        chapter: isChapter('WCoF-1', { 'WCoF-1': entry({ id: 'WCoF-1', isParent: true }) }),
        leaf: isChapter('WCoF-1-1', { 'WCoF-1-1': entry({ id: 'WCoF-1-1', isParent: false }) }),
      }),
      expected: {
        chapter: true,
        leaf: false,
      },
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});

describe('regex state regressions', () => {
  const cases = {
    'parseFacets remains stable across repeated keyword searches': {
      actual: () => [parseFacets('westminster standards'), parseFacets('westminster standards')],
      expected: [
        [[
          'document:Westminster Shorter Catechism',
          'document:Westminster Larger Catechism',
          'document:Westminster Confession of Faith',
        ]],
        [[
          'document:Westminster Shorter Catechism',
          'document:Westminster Larger Catechism',
          'document:Westminster Confession of Faith',
        ]],
      ],
    },
    'getPageTitle remains stable across repeated keyword searches': {
      actual: () => [getPageTitle('three forms of unity'), getPageTitle('three forms of unity')],
      expected: [
        ['The Three Forms Of Unity', null],
        ['The Three Forms Of Unity', null],
      ],
    },
  };

  defineCases(cases, ({ actual, expected }) => {
    expect(actual()).toEqual(expected);
  });
});
