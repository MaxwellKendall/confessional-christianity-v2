import { describe, expect, test } from 'vitest';

import {
  getAllSeries, getSeries, partDevotion, seriesForSeason, seriesMembership,
} from '@/lib/devotionSeries';
import { SEASONS, devotionsGroundedIn, getDevotion } from '@/lib/devotions';

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

  test('each series opens from a real season and fills its whole run', () => {
    getAllSeries().forEach((series) => {
      const season = SEASONS.find((s) => s.slug === series.season);
      expect(season, series.slug).toBeDefined();
      expect(series.parts).toHaveLength(season!.days);
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

  test('advent is Prepare the Way, with the annunciation at part 9 (16a)', () => {
    const advent = getSeries('advent')!;
    expect(advent.title).toBe('Prepare the Way');
    expect(seriesForSeason('advent')).toBe(advent);
    expect(advent.parts[8]).toEqual({
      day: 9, title: 'The Annunciation', citation: 'Luke 1:26–38',
    });
  });
});

describe('parts and their devotions', () => {
  const advent = () => getSeries('advent')!;

  test('an authored part resolves to its season-grounded devotion', () => {
    expect(partDevotion(advent(), 1)).toBe(getDevotion('advent-1'));
    expect(partDevotion(advent(), 3)).toBe(getDevotion('advent-3'));
  });

  test('a part still in preparation resolves to null', () => {
    expect(partDevotion(advent(), 24)).toBeNull();
  });

  test('authored parts run contiguously from day 1 — sequential unlock never strands', () => {
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

  test('a standalone devotion belongs to no series', () => {
    expect(seriesMembership(getDevotion('psalm-130')!)).toBeNull();
  });
});
