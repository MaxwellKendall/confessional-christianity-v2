// Devotion series (turn 16, generalized in turn 17): the seasonal and
// catechism rows both open onto genuine series — ordered, cumulative runs
// where part 9 presumes the household has prayed through parts 1–8. A
// single devotion (turn 15) stays the base unit; a series is an ordering
// over it, regardless of which axis grounds the devotions inside it (a
// season's days, or a catechism's questions). The manifest names every part
// up front (title and citation) and points at its devotion by slug — a
// direct reference rather than a grounding-field match, since a catechism
// part can span more than one entry id. Order is purely sequential: a part
// unlocks when the one before it is finished, with no date attached.
import adventSeries from '../../content/devotions/series/advent.json';
import wscSeries from '../../content/devotions/series/wsc.json';
import { getDocumentById } from './catechisms';
import { getDevotion, SEASONS, type Devotion } from './devotions';

export type SeriesSource =
  | { kind: 'season'; season: string }
  | { kind: 'catechism'; documentId: string };

export interface SeriesPart {
  /** 1-based position in the series. */
  day: number;
  title: string;
  /** The passage or question the part moves through, named even before
   * it's authored — the 16a part list shows the whole arc, locked parts
   * included. */
  citation: string;
  /** The devotion carrying this part's content — absent while the part is
   * still in preparation. */
  devotionSlug?: string;
}

export interface DevotionSeries {
  slug: string;
  /** What axis this run is ordered over — a season's days, or a
   * catechism's questions. */
  source: SeriesSource;
  /** The series' own name ("Prepare the Way"), distinct from the source's. */
  title: string;
  /** The 16a subtitle: "Waiting, Longing, Fulfillment". */
  tagline: string;
  /** The landing page's paragraph — the arc, and that it's cumulative. */
  description: string;
  parts: SeriesPart[];
}

// Add a static import + entry here for each authored series, same shape as
// advent. Slugs share the /devotions/[slug] namespace with devotions.
const SERIES: DevotionSeries[] = [
  adventSeries as DevotionSeries,
  wscSeries as DevotionSeries,
];

export const getAllSeries = (): DevotionSeries[] => SERIES;

export const getSeries = (slug: string): DevotionSeries | null => SERIES
  .find((s) => s.slug === slug) ?? null;

export const seriesForSeason = (season: string): DevotionSeries | null => SERIES
  .find((s) => s.source.kind === 'season' && s.source.season === season) ?? null;

export const seriesForCatechism = (documentId: string): DevotionSeries | null => SERIES
  .find((s) => s.source.kind === 'catechism' && s.source.documentId === documentId) ?? null;

/** What the hub/landing calls this run's source: the season's name, or the
 * catechism document's name. Falls back to the series' own title. */
export const seriesSourceLabel = (series: DevotionSeries): string => {
  const { source } = series;
  if (source.kind === 'season') {
    return SEASONS.find((s) => s.slug === source.season)?.name ?? series.title;
  }
  return getDocumentById(source.documentId)?.name ?? series.title;
};

/** How many catechism questions this run has actually authored so far —
 * summed off each part's devotion, since a part can profess more than one
 * question. Zero for a season-sourced run. */
export const catechismQuestionsAuthored = (series: DevotionSeries): number => series.parts
  .reduce((sum, part) => {
    const devotion = part.devotionSlug ? getDevotion(part.devotionSlug) : null;
    return devotion?.grounding.kind === 'catechism' ? sum + devotion.grounding.entryIds.length : sum;
  }, 0);

/** The devotion carrying a part's authored content — null while the part is
 * still in preparation. */
export const partDevotion = (series: DevotionSeries, day: number): Devotion | null => {
  const part = series.parts.find((p) => p.day === day);
  return part?.devotionSlug ? getDevotion(part.devotionSlug) : null;
};

export interface SeriesMembership {
  series: DevotionSeries;
  part: SeriesPart;
}

/** Which series a devotion is a part of, and where in the order — null for
 * standalone devotions. Finishing a member part records series progress and
 * returns to the series, not the devotion's own landing. */
export const seriesMembership = (devotion: Devotion): SeriesMembership | null => {
  for (const series of SERIES) {
    const part = series.parts.find((p) => p.devotionSlug === devotion.slug);
    if (part) return { series, part };
  }
  return null;
};
