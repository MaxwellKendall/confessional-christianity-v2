// Devotion series (turn 16): the seasonal rows open onto genuine series —
// ordered, cumulative runs where part 9 presumes the household has prayed
// through parts 1–8. A single devotion (turn 15) stays the base unit; a
// series is an ordering over it. The manifest names every part up front
// (title and citation), while a part's actual content is a season-grounded
// devotion whose day matches — authored parts run contiguously from day 1,
// and the rest are listed but still in preparation, the same honest
// degradation the hub rows use. Order is purely sequential: a part unlocks
// when the one before it is finished, with no date attached.
import adventSeries from '../../content/devotions/series/advent.json';
import { getAllDevotions, type Devotion } from './devotions';

export interface SeriesPart {
  /** 1-based position in the series — the same `day` a season grounding
   * carries, so part n's content is the devotion grounded on day n. */
  day: number;
  title: string;
  /** The passage the part moves through, named even before it's authored —
   * the 16a part list shows the whole arc, locked parts included. */
  citation: string;
}

export interface DevotionSeries {
  slug: string;
  /** A slug into SEASONS — the hub row this series opens from. */
  season: string;
  /** The series' own name ("Prepare the Way"), distinct from the season's. */
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
];

export const getAllSeries = (): DevotionSeries[] => SERIES;

export const getSeries = (slug: string): DevotionSeries | null => SERIES
  .find((s) => s.slug === slug) ?? null;

export const seriesForSeason = (season: string): DevotionSeries | null => SERIES
  .find((s) => s.season === season) ?? null;

/** The devotion carrying a part's authored content — null while the part is
 * still in preparation. */
export const partDevotion = (series: DevotionSeries, day: number): Devotion | null => getAllDevotions()
  .find((d) => d.grounding.kind === 'season'
    && d.grounding.season === series.season
    && d.grounding.day === day) ?? null;

export interface SeriesMembership {
  series: DevotionSeries;
  part: SeriesPart;
}

/** Which series a devotion is a part of, and where in the order — null for
 * standalone devotions. Finishing a member part records series progress and
 * returns to the series, not the devotion's own landing. */
export const seriesMembership = (devotion: Devotion): SeriesMembership | null => {
  const { grounding } = devotion;
  if (grounding.kind !== 'season') return null;
  const series = seriesForSeason(grounding.season);
  const part = series?.parts.find((p) => p.day === grounding.day);
  return series && part ? { series, part } : null;
};
