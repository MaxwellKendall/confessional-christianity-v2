import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, test } from 'vitest';

import { catechismSeriesParts } from '@/lib/admin/catechismParts';
import { blankDevotion, devotionFrom } from '@/lib/admin/devotionDraft';
import { getAllSeries, getSeries, type DevotionSeries } from '@/lib/devotionSeries';
import {
  DEVOTION_ROLES, findSeriesLink, mergeSeriesEdit, relinkSeries, toContentJson, validateDevotion, validateSeries,
} from '@/lib/devotionValidation';
import { getAllDevotions, getDevotion } from '@/lib/devotions';

const contentDir = path.resolve(__dirname, '../content/devotions');
const psalm130 = () => structuredClone(getDevotion('psalm-130')!);

describe('the generated manifest', () => {
  test('carries every devotion and series file on disk', () => {
    const files = (dir: string) => readdirSync(dir).filter((f) => f.endsWith('.json')).length;
    expect(getAllDevotions()).toHaveLength(files(contentDir));
    expect(getAllSeries()).toHaveLength(files(path.join(contentDir, 'series')));
  });
});

describe('every authored file meets the contract /admin enforces', () => {
  test.each(getAllDevotions().map((d) => [d.slug, d] as const))('%s', (_slug, devotion) => {
    expect(validateDevotion(devotion)).toEqual([]);
  });

  test.each(getAllSeries().map((s) => [s.slug, s] as const))('series %s', (_slug, series) => {
    expect(validateSeries(series, { otherSeries: getAllSeries() })).toEqual([]);
  });

});

describe('the admin writes files in their existing layout', () => {
  const files = [contentDir, path.join(contentDir, 'series')].flatMap((dir) => readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => [path.relative(contentDir, path.join(dir, f)), readFileSync(path.join(dir, f), 'utf8')] as const));

  test('re-saving an untouched file is byte-identical', () => {
    const drifted = files
      .filter(([, text]) => toContentJson(JSON.parse(text), text) !== text)
      .map(([name]) => name);
    // psalm-130 mixes layouts by hand; its first admin save normalizes it
    expect(drifted).toEqual(['psalm-130.json']);
  });

  test('moving a series part changes only that part’s line', () => {
    const original = readFileSync(path.join(contentDir, 'series/advent.json'), 'utf8');
    const [advent] = relinkSeries(getAllSeries(), 'advent-4', { seriesSlug: 'advent', day: 4 });
    const before = original.split('\n');
    const after = toContentJson(advent, original).split('\n');
    expect(after).toHaveLength(before.length);
    expect(after.filter((line, i) => line !== before[i])).toEqual([
      '    { "day": 4, "title": "A Prophet Like Moses", "citation": "Deuteronomy 18:15–19", "devotionSlug": "advent-4" },',
    ]);
  });

  test('new files come out fully expanded, like the generated WSC run', () => {
    const wsc51 = readFileSync(path.join(contentDir, 'wsc-51.json'), 'utf8');
    expect(toContentJson(getDevotion('wsc-51'))).toBe(wsc51);
  });
});

describe('validateDevotion rejects what the renderer cannot show', () => {
  test('a malformed or taken slug', () => {
    expect(validateDevotion({ ...psalm130(), slug: 'Psalm 23' })[0]).toMatch(/^slug/);
    expect(validateDevotion(psalm130(), { takenSlugs: ['psalm-130'] })).toEqual(['slug "psalm-130" is already taken']);
  });

  test('steps out of the service order', () => {
    const devotion = psalm130();
    devotion.steps.reverse();
    expect(validateDevotion(devotion).join('\n')).toMatch(/eight service roles in order/);
  });

  test('a step with nothing in it', () => {
    const devotion = psalm130();
    devotion.steps[2].elements = [];
    expect(validateDevotion(devotion)).toEqual(['Receiving Forgiveness needs at least one element']);
  });

  test('missing element fields', () => {
    const devotion = psalm130();
    devotion.steps[0].elements = [{ type: 'scripture', citation: 'Psalm 1', osis: '', text: '' }];
    expect(validateDevotion(devotion)).toEqual([
      'Call to Worship › element 1.osis is required',
      'Call to Worship › element 1.text is required',
    ]);
  });

  test('groundings outside the registries', () => {
    expect(validateDevotion({ ...psalm130(), grounding: { kind: 'topic', topic: 'nope' } })[0]).toMatch(/grounding.topic/);
    expect(validateDevotion({ ...psalm130(), grounding: { kind: 'season', season: 'advent', day: 25 } })[0]).toMatch(/1 to 24/);
    expect(validateDevotion({ ...psalm130(), grounding: { kind: 'catechism', entryIds: ['XYZ-1'] } })[0]).toMatch(/not a known/);
    expect(validateDevotion({ ...psalm130(), grounding: { kind: 'catechism', entryIds: ['WSC-1', 'WLC-1'] } })).toEqual([
      'grounding.entryIds must all come from one document',
    ]);
  });
});

describe('editor starting points', () => {
  test('a blank devotion has the eight roles but needs filling in', () => {
    const blank = blankDevotion();
    expect(blank.steps.map((s) => s.role)).toEqual(DEVOTION_ROLES);
    expect(validateDevotion(blank).length).toBeGreaterThan(0);
  });

  test('a copy keeps the liturgy and clears the identity', () => {
    const copy = devotionFrom(getDevotion('psalm-130')!);
    expect(copy.slug).toBe('');
    expect(copy.steps).toEqual(getDevotion('psalm-130')!.steps);
    expect(copy.steps).not.toBe(getDevotion('psalm-130')!.steps);
  });
});

describe('series linking', () => {
  const series = () => structuredClone(getAllSeries());

  test('finds where a devotion sits', () => {
    expect(findSeriesLink(series(), 'advent-2')).toEqual({ seriesSlug: 'advent', day: 2 });
    expect(findSeriesLink(series(), 'psalm-130')).toBeNull();
  });

  test('linking a devotion to an open part changes only that series', () => {
    const changed = relinkSeries(series(), 'advent-4', { seriesSlug: 'advent', day: 4 });
    expect(changed.map((s) => s.slug)).toEqual(['advent']);
    expect(changed[0].parts[3].devotionSlug).toBe('advent-4');
  });

  test('moving a devotion clears its old part', () => {
    const [advent] = relinkSeries(series(), 'advent-3', { seriesSlug: 'advent', day: 5 });
    expect(advent.parts[2].devotionSlug).toBeUndefined();
    expect('devotionSlug' in advent.parts[2]).toBe(false);
    expect(advent.parts[4].devotionSlug).toBe('advent-3');
  });

  test('unlinking and no-op saves', () => {
    expect(relinkSeries(series(), 'advent-3', { seriesSlug: 'advent', day: 3 })).toEqual([]);
    const [advent] = relinkSeries(series(), 'advent-3', null);
    expect(advent.parts[2].devotionSlug).toBeUndefined();
  });

  test('never takes over a part another devotion fills', () => {
    expect(() => relinkSeries(series(), 'psalm-130', { seriesSlug: 'advent', day: 1 }))
      .toThrow(/already belongs to "advent-1"/);
    expect(() => relinkSeries(series(), 'x', { seriesSlug: 'lent', day: 1 })).toThrow(/does not exist/);
  });
});

describe('validateSeries', () => {
  const lent = (): DevotionSeries => ({
    slug: 'lent',
    source: { kind: 'season', season: 'lent' },
    title: 'The Way of the Cross',
    tagline: 'Forty Days',
    description: 'A walk to Good Friday.',
    parts: [{ day: 1, title: 'Dust', citation: 'Genesis 3:19' }],
  });

  test('a complete new series passes', () => {
    expect(validateSeries(lent(), { takenSlugs: ['advent', 'wsc'], otherSeries: getAllSeries() })).toEqual([]);
  });

  test('missing names, empty parts, and malformed days', () => {
    expect(validateSeries({ ...lent(), title: '', tagline: ' ', parts: [] })).toEqual([
      'title is required', 'tagline is required', 'a series needs at least one part',
    ]);
    expect(validateSeries({ ...lent(), parts: [{ day: 2, title: '', citation: 'x' }] })).toEqual([
      'part 1 has day 2', 'part 1 needs a title',
    ]);
  });

  test('sources must exist, and one series per season or document', () => {
    expect(validateSeries({ ...lent(), source: { kind: 'season', season: 'easter' } })[0]).toMatch(/source.season/);
    expect(validateSeries({ ...lent(), source: { kind: 'catechism', documentId: 'NOPE' } })[0]).toMatch(/known document/);
    expect(validateSeries({ ...lent(), slug: 'advent-2026', source: { kind: 'season', season: 'advent' } }, { otherSeries: getAllSeries() }))
      .toEqual(['"Prepare the Way" (advent) already covers this season']);
    expect(validateSeries({ ...lent(), slug: 'wsc', source: { kind: 'catechism', documentId: 'WSC' } }, { otherSeries: getAllSeries() }))
      .toEqual([]);
  });

  test('a season series fits in the season', () => {
    const parts = Array.from({ length: 41 }, (_, i) => ({ day: i + 1, title: 't', citation: 'c' }));
    expect(validateSeries({ ...lent(), parts })).toEqual(["Lent has 40 days, so its series can't have 41 parts"]);
  });
});

describe('mergeSeriesEdit', () => {
  const advent = () => structuredClone(getSeries('advent')!);

  test('keeps devotion links by day and ignores links sent with the edit', () => {
    const draft = advent();
    draft.parts[0].title = 'Retitled';
    draft.parts[4].devotionSlug = 'smuggled';
    delete draft.parts[1].devotionSlug;
    const merged = mergeSeriesEdit(draft, advent(), advent());
    expect(merged.parts[0]).toEqual({ day: 1, title: 'Retitled', citation: 'Genesis 3:8–15', devotionSlug: 'advent-1' });
    expect(merged.parts[1].devotionSlug).toBe('advent-2');
    expect(merged.parts[4].devotionSlug).toBeUndefined();
  });

  test('parts can be added after the published ones but not removed', () => {
    const longer = { ...advent(), parts: [...advent().parts.slice(0, 3)] };
    expect(() => mergeSeriesEdit(longer, advent(), advent())).toThrow(/added but not removed/);
    // unpublished: trailing parts may go, until a linked one would
    expect(mergeSeriesEdit(longer, advent(), null).parts).toHaveLength(3);
    const tooShort = { ...advent(), parts: advent().parts.slice(0, 2) };
    expect(() => mergeSeriesEdit(tooShort, advent(), null)).toThrow(/part 3 has a devotion linked/);
  });

  test('renumbers days from position', () => {
    const draft = { ...advent(), parts: advent().parts.map((p) => ({ ...p, day: 99 })) };
    expect(mergeSeriesEdit(draft, advent(), advent()).parts.map((p) => p.day).slice(0, 3)).toEqual([1, 2, 3]);
  });
});

describe('catechism prefill', () => {
  test('one part per question, titled from the catechism', () => {
    const wsc = catechismSeriesParts('WSC');
    expect(wsc).toHaveLength(107);
    expect(wsc[0]).toEqual({ day: 1, title: 'What is the chief end of man?', citation: 'WSC Q. 1' });
    expect(catechismSeriesParts('WLC')).toHaveLength(196);
  });

  test("grouped documents get one part per group (the Heidelberg's Lord's Days)", () => {
    const hc = catechismSeriesParts('HC');
    expect(hc).toHaveLength(52);
    expect(hc[0]).toEqual({ day: 1, title: "LORD's Day 1", citation: "HC LORD's Day 1" });
  });

  test('unknown documents give nothing', () => {
    expect(catechismSeriesParts('NOPE')).toEqual([]);
  });
});
