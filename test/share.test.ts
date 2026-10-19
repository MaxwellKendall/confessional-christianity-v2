import { describe, expect, test } from 'vitest';

import { loadConfessionContent } from '@/lib/confessionContent';
import type { ConfessionEntry } from '@/lib/domain';
import {
  MAX_QUOTE_CHARS, buildShareQuote, clauseSpans, contextPath, parseSelection, readingText,
  selectionQuery, sharePath, shareText,
} from '@/lib/share';
import { resolveShare } from '@/lib/shareContent';

const entryOf = async (slug: string, id: string): Promise<ConfessionEntry> => {
  const content = await loadConfessionContent(slug);
  return content!.contentById[id];
};

describe('reading text and clause spans', () => {
  test('spans tile the reading text, each closed by its marker', async () => {
    const wsc1 = await entryOf('westminster-shorter-catechism', 'WSC-1');
    expect(readingText(wsc1)).toBe("Man's chief end is to glorify God, and to enjoy him for ever.");
    expect(clauseSpans(wsc1)).toEqual([
      { start: 0, end: 34, text: "Man's chief end is to glorify God,", marker: 'a' },
      { start: 34, end: 61, text: ' and to enjoy him for ever.', marker: 'b' },
    ]);
  });
});

describe('selection URLs', () => {
  test('round-trip through the query string', () => {
    for (const selection of [
      { kind: 'entry' as const },
      { kind: 'clause' as const, marker: 'b' },
      { kind: 'range' as const, start: 4, end: 40 },
    ]) {
      expect(parseSelection(new URLSearchParams(selectionQuery(selection)))).toEqual(selection);
    }
  });

  test('mangled params open the whole entry', () => {
    expect(parseSelection({ c: '<script>' })).toEqual({ kind: 'entry' });
    expect(parseSelection({ r: '40-4' })).toEqual({ kind: 'entry' });
    expect(parseSelection({ r: ['3-9', 'x'] })).toEqual({ kind: 'range', start: 3, end: 9 });
  });

  test('share and context paths', () => {
    expect(sharePath('westminster-shorter-catechism', '1', { kind: 'clause', marker: 'a' }))
      .toBe('/share/westminster-shorter-catechism/1?c=a');
    expect(sharePath('westminster-shorter-catechism', '1', { kind: 'entry' })).toBe('/share/westminster-shorter-catechism/1');
    expect(contextPath('heidelberg-catechism', '1-1', { kind: 'range', start: 2, end: 9 }))
      .toBe('/library/heidelberg-catechism/1-1#r-2-9');
  });
});

describe('buildShareQuote', () => {
  test('a whole catechism answer carries every proof text, in order', async () => {
    const quote = buildShareQuote(await entryOf('westminster-shorter-catechism', 'WSC-1'), { kind: 'entry' })!;
    expect(quote.question).toBe('What is the chief end of man?');
    expect(quote.quote).toBe("Man's chief end is to glorify God, and to enjoy him for ever.");
    expect(quote.refs.map((r) => r.osis)).toEqual(['1Cor.10.31', 'Rom.11.36', 'Ps.73.25-Ps.73.28']);
  });

  test('a clause carries only its own proof texts, with ellipses where it cuts', async () => {
    const wsc1 = await entryOf('westminster-shorter-catechism', 'WSC-1');
    expect(buildShareQuote(wsc1, { kind: 'clause', marker: 'a' })).toMatchObject({
      quote: "Man's chief end is to glorify God…",
      refs: [{ osis: '1Cor.10.31', citation: '1 Corinthians 10:31' }, { osis: 'Rom.11.36' }],
    });
    expect(buildShareQuote(wsc1, { kind: 'clause', marker: 'b' })).toMatchObject({
      quote: '…and to enjoy him for ever.',
      refs: [{ osis: 'Ps.73.25-Ps.73.28' }],
    });
    expect(buildShareQuote(wsc1, { kind: 'clause', marker: 'z' })).toBeNull();
  });

  test('a selection snaps to whole words and takes the proof texts of every clause it touches', async () => {
    const wsc1 = await entryOf('westminster-shorter-catechism', 'WSC-1');
    // "lorify God, and to enjo" — ragged at both ends, spanning both clauses
    const quote = buildShareQuote(wsc1, { kind: 'range', start: 23, end: 46 })!;
    expect(quote.quote).toBe('…glorify God, and to enjoy…');
    expect(quote.selection).toEqual({ kind: 'range', start: 22, end: 47 });
    expect(quote.refs.map((r) => r.osis)).toEqual(['1Cor.10.31', 'Rom.11.36', 'Ps.73.25-Ps.73.28']);
    expect(buildShareQuote(wsc1, { kind: 'range', start: 34, end: 35 })).toBeNull();
  });

  test('long passages are capped at a word boundary', async () => {
    const wcf = await entryOf('westminster-confession-of-faith', 'WCoF-1-1');
    const quote = buildShareQuote(wcf, { kind: 'entry' })!;
    expect(quote.quote.length).toBeLessThanOrEqual(MAX_QUOTE_CHARS + 1);
    expect(quote.quote.endsWith('…')).toBe(true);
    expect(quote.question).toBeNull();
  });

  test('entries without proof texts still share', async () => {
    const thesis = await entryOf('martin-luthers-95-theses', 'ML9t-1');
    expect(buildShareQuote(thesis, { kind: 'entry' })).toMatchObject({ refs: [], question: null });
  });
});

describe('shareText', () => {
  test('reads as a quote with its source, Scripture, and link', async () => {
    const quote = buildShareQuote(await entryOf('westminster-shorter-catechism', 'WSC-1'), { kind: 'clause', marker: 'b' })!;
    expect(shareText(quote, { source: 'Westminster Shorter Catechism, Q. 1', url: 'https://x/s' })).toBe([
      'Q. What is the chief end of man?',
      'A. …and to enjoy him for ever.',
      '— Westminster Shorter Catechism, Q. 1',
      '',
      'Scripture: Psalms 73:25-28',
      '',
      'https://x/s',
    ].join('\n'));
  });
});

describe('resolveShare', () => {
  test('resolves a share URL to its source line and paths', async () => {
    const share = await resolveShare('westminster-shorter-catechism', '1', { kind: 'clause', marker: 'a' });
    expect(share).toMatchObject({
      label: 'Q. 1',
      source: 'Westminster Shorter Catechism, Q. 1',
      path: '/share/westminster-shorter-catechism/1?c=a',
      context: '/library/westminster-shorter-catechism/1#c-a',
    });
  });

  test('an unknown marker falls back to the whole entry; an unknown entry is null', async () => {
    const share = await resolveShare('westminster-shorter-catechism', '1', { kind: 'clause', marker: 'q' });
    expect(share?.quote.selection).toEqual({ kind: 'entry' });
    expect(await resolveShare('westminster-shorter-catechism', '999', { kind: 'entry' })).toBeNull();
  });
});
