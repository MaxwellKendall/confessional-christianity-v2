import { describe, expect, test } from 'vitest';

import { citationToOsis, parseOsisBibleReference } from '@/lib/bible';
import {
  clauseForMarker,
  entryQuoteSegments,
  entryTextSegments,
  proofTextGroups,
} from '@/lib/entryDisplay';
import { parseCitedById } from '@/lib/helpers';
import { getAllScriptureParams, getScriptureCitingEntries } from '@/lib/scripture';
import type { ConfessionEntry } from '@/lib/domain';
import { defineCases } from './support/defineCases';

const wlc50: ConfessionEntry = {
  id: 'WLC-50',
  parent: 'WLC',
  isParent: false,
  title: "Question 50: Wherein consisted Christ's humiliation after his death?",
  text: "Christ's humiliation after his death consisted in his being buried,[1] and continuing in the state of the dead, and under the power of death till the third day;[2] which hath been otherwise expressed in these words, he descended into hell.",
  verses: {
    1: ['1Cor.15.3-1Cor.15.4'],
    2: ['Ps.16.10', 'Acts.2.24-Acts.2.27', 'Acts.2.31', 'Rom.6.9', 'Matt.12.40'],
  },
};

describe('citationToOsis', () => {
  defineCases<{ input: string; expected: string | null }>({
    'single verse': { input: 'Acts 2:31', expected: 'Acts.2.31' },
    'verse range with en dash, as the ESV canonicalizes': {
      input: 'Acts 2:24–27',
      expected: 'Acts.2.24-Acts.2.27',
    },
    'numbered book': { input: '1 Corinthians 15:3–4', expected: '1Cor.15.3-1Cor.15.4' },
    'ESV singular Psalm': { input: 'Psalm 16:10', expected: 'Ps.16.10' },
    'cross-chapter range': { input: 'Acts 1:1–2:4', expected: 'Acts.1.1-Acts.2.4' },
    'plain hyphen range': { input: 'Romans 8:1-4', expected: 'Rom.8.1-Rom.8.4' },
    'whole chapter': { input: 'Psalm 73', expected: 'Ps.73' },
    'chapter range': { input: 'Hebrews 8–10', expected: 'Heb.8-Heb.10' },
    'single-chapter book': { input: 'Jude 4', expected: 'Jude.1.4' },
    'single-chapter book range': { input: 'Jude 20–21', expected: 'Jude.1.20-Jude.1.21' },
    'unknown book fails soft': { input: 'Maccabees 1:1', expected: null },
    'not a citation fails soft': { input: 'chief end of man', expected: null },
  }, ({ input, expected }) => {
    expect(citationToOsis(input)).toBe(expected);
  });

  test('round-trips the refs stored in normalized data', () => {
    const refs = ['Ps.73.24-Ps.73.28', '2Tim.3.15-2Tim.3.17', 'Matt.12.40', 'Song.2.16'];
    refs.forEach((osis) => {
      expect(citationToOsis(parseOsisBibleReference(osis))).toBe(osis);
    });
  });
});

describe('parseCitedById', () => {
  defineCases<{ input: string; expected: { entryId: string; label: string } }>({
    'WCF chapter/article with letter marker': {
      input: 'WCoF-10-3-a',
      expected: { entryId: 'WCoF-10-3', label: 'Westminster Confession 10.3' },
    },
    'WLC question with numeric marker': {
      input: 'WLC-50-2',
      expected: { entryId: 'WLC-50', label: 'Larger Catechism Q. 50' },
    },
    'WSC question with letter marker': {
      input: 'WSC-27-g',
      expected: { entryId: 'WSC-27', label: 'Shorter Catechism Q. 27' },
    },
    "Heidelberg LORD's day + Q&A with letter marker": {
      input: 'HC-6-17-d',
      expected: { entryId: 'HC-6-17', label: 'Heidelberg Catechism Q&A 17' },
    },
  }, ({ input, expected }) => {
    expect(parseCitedById(input)).toEqual(expected);
  });
});

describe('entryTextSegments / clauseForMarker', () => {
  test('splits the text at markers, each clause keyed by the marker closing it', () => {
    const segments = entryTextSegments(wlc50.text);
    expect(segments).toHaveLength(3);
    expect(segments[0]).toEqual({
      text: "Christ's humiliation after his death consisted in his being buried,",
      marker: '1',
    });
    expect(segments[1].marker).toBe('2');
    expect(segments[2].marker).toBeUndefined();
  });

  test('clauseForMarker returns the clause a citation actually supports', () => {
    expect(clauseForMarker(wlc50, '2')).toBe(
      'and continuing in the state of the dead, and under the power of death till the third day;',
    );
    expect(clauseForMarker(wlc50, 'z')).toBe('');
  });
});

describe('entryQuoteSegments', () => {
  test('keeps Q&A shape with markers preserved in the answer line', () => {
    const lines = entryQuoteSegments(wlc50);
    expect(lines).toHaveLength(2);
    expect(lines[0]).toEqual([{ text: "Q. Wherein consisted Christ's humiliation after his death?" }]);
    expect(lines[1][0]).toEqual({ text: 'A. ' });
    expect(lines[1][1].marker).toBe('1');
  });
});

describe('proofTextGroups', () => {
  test('groups refs by marker in text order with human citations', () => {
    const groups = proofTextGroups(wlc50);
    expect(groups.map((g) => g.marker)).toEqual(['1', '2']);
    expect(groups[0].refs).toEqual([
      { osis: '1Cor.15.3-1Cor.15.4', citation: '1 Corinthians 15:3-4' },
    ]);
    expect(groups[1].refs.map((r) => r.citation)).toContain('Psalms 16:10');
  });

  test('returns nothing for entries without proof texts', () => {
    expect(proofTextGroups({ ...wlc50, verses: undefined })).toEqual([]);
  });
});

describe('scripture index', () => {
  test('inverts every proof text into a canonical page param', async () => {
    const params = await getAllScriptureParams();
    expect(params.length).toBeGreaterThan(2000);
    expect(params).toContainEqual({ osis: 'Acts.2.24-Acts.2.27' });
  });

  test('a ref cited across documents lists each citing clause with its entry link', async () => {
    const citing = await getScriptureCitingEntries('Acts.2.24-Acts.2.27');
    const wlc = citing.find((c) => c.entryId === 'WLC-50');
    expect(wlc).toBeDefined();
    expect(wlc!.documentTitle).toBe('Westminster Larger Catechism');
    expect(wlc!.entryLabel).toBe('Q. 50');
    expect(wlc!.href).toBe('/library/westminster-larger-catechism/50');
    expect(wlc!.clause).toContain('till the third day');
    // the same verse anchors WSC Q. 27's footnote too
    expect(citing.some((c) => c.entryId === 'WSC-27')).toBe(true);
  });

  test('unknown refs yield no citing entries', async () => {
    expect(await getScriptureCitingEntries('Gen.99.99')).toEqual([]);
  });
});
