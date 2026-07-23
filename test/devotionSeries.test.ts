import { describe, expect, test } from 'vitest';

import {
  catechismQuestionsAuthored, getAllSeries, getSeries, partDevotion,
  seriesForCatechism, seriesForSeason, seriesMembership, seriesSourceLabel,
} from '@/lib/devotionSeries';
import {
  SEASONS, devotionsGroundedIn, getDevotion,
} from '@/lib/devotions';

describe('the series manifest', () => {
  test('every series is retrievable by its slug', () => {
    getAllSeries().forEach((series) => {
      expect(getSeries(series.slug)).toBe(series);
    });
    expect(getSeries('christmastide')).toBeNull();
  });

  test('series slugs share the /devotions/[slug] namespace without colliding', () => {
    getAllSeries().forEach((series) => {
      expect(getDevotion(series.slug)).toBeNull();
    });
  });

  test('parts are numbered 1..n in order, each with a title and citation', () => {
    getAllSeries().forEach((series) => {
      expect(series.parts.map((p) => p.day))
        .toEqual(series.parts.map((_, i) => i + 1));
      series.parts.forEach((part) => {
        expect(part.title).toBeTruthy();
        expect(part.citation).toBeTruthy();
      });
    });
  });

  test('advent is season-sourced, Prepare the Way, with the annunciation at part 9 (16a)', () => {
    const advent = getSeries('advent')!;
    expect(advent.source).toEqual({ kind: 'season', season: 'advent' });
    expect(advent.title).toBe('Prepare the Way');
    expect(seriesForSeason('advent')).toBe(advent);
    expect(seriesSourceLabel(advent)).toBe('Advent');
    expect(advent.parts).toHaveLength(SEASONS.find((s) => s.slug === 'advent')!.days);
    expect(advent.parts[8]).toEqual({
      day: 9, title: 'The Annunciation', citation: 'Luke 1:26–38',
    });
  });

  test('wsc is catechism-sourced, ordered by question', () => {
    const wsc = getSeries('wsc')!;
    expect(wsc.source).toEqual({ kind: 'catechism', documentId: 'WSC' });
    expect(seriesForCatechism('WSC')).toBe(wsc);
    expect(seriesSourceLabel(wsc)).toBe('Westminster Shorter Catechism');
    expect(wsc.parts[0]).toMatchObject({ day: 1, citation: 'WSC Q. 1', devotionSlug: 'wsc-1' });
  });

  test('catechismQuestionsAuthored sums a part\'s covered questions, including paired parts', () => {
    const wsc = getSeries('wsc')!;
    // wsc-1 covers Q1 alone; the run pairs some later parts (e.g. Q40 & 41)
    // into one devotion, so total questions authored exceeds part count.
    expect(catechismQuestionsAuthored(wsc)).toBeGreaterThan(wsc.parts.length);
    expect(catechismQuestionsAuthored(wsc)).toBe(66);
  });
});

describe('parts and their devotions', () => {
  const advent = () => getSeries('advent')!;
  const wsc = () => getSeries('wsc')!;

  test('an authored part resolves to its devotion, by slug', () => {
    expect(partDevotion(advent(), 1)).toBe(getDevotion('advent-1'));
    expect(partDevotion(advent(), 3)).toBe(getDevotion('advent-3'));
    expect(partDevotion(wsc(), 1)).toBe(getDevotion('wsc-1'));
  });

  test('a part still in preparation resolves to null', () => {
    expect(partDevotion(advent(), 24)).toBeNull();
  });

  test('authored parts run contiguously from day 1 — the Continue suggestion never strands behind a gap', () => {
    getAllSeries().forEach((series) => {
      const authored = series.parts.map((p) => partDevotion(series, p.day) !== null);
      const frontier = authored.indexOf(false);
      const past = frontier === -1 ? [] : authored.slice(frontier);
      expect(past.some(Boolean), series.slug).toBe(false);
    });
  });

  test('every season-grounded devotion is a listed part of its series', () => {
    devotionsGroundedIn('season').forEach((devotion) => {
      const membership = seriesMembership(devotion);
      expect(membership, devotion.slug).not.toBeNull();
      expect(partDevotion(membership!.series, membership!.part.day)).toBe(devotion);
    });
  });

  test('every catechism-grounded devotion is a listed part of the wsc run', () => {
    devotionsGroundedIn('catechism').forEach((devotion) => {
      const membership = seriesMembership(devotion);
      expect(membership, devotion.slug).not.toBeNull();
      expect(membership!.series.slug).toBe('wsc');
      expect(partDevotion(membership!.series, membership!.part.day)).toBe(devotion);
    });
  });

  test('a devotion pairing two questions is one part, not two', () => {
    const pairedDevotion = getDevotion('wsc-40')!;
    expect(pairedDevotion.grounding).toEqual({ kind: 'catechism', entryIds: ['WSC-40', 'WSC-41'] });
    const membership = seriesMembership(pairedDevotion)!;
    expect(membership.part.citation).toBe('WSC Q. 40–41');
  });

  test('a standalone devotion belongs to no series', () => {
    expect(seriesMembership(getDevotion('psalm-130')!)).toBeNull();
  });
});
