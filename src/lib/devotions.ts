// Devotions (turn 15): the liturgy object generalized into a curated,
// browsable library. Family Worship's liturgies (worship.ts) are keyed by
// daypart and rotate content daily; a devotion is a fixed, addressable
// liturgy grounded in something specific — a Scripture range, a topic, a
// catechism entry, or a season — never generic filler. Its steps are the
// same typed elements the eight-step worship shell already renders, so
// "Begin This Devotion" (mockup 15c) hands off to the existing renderer;
// only the wrapper metadata (grounding, summary, description) is new.
// "Liturgy" stays out of user-facing copy — everywhere it's "Devotions".
// Statically imported so the bundler traces the data (see programContent.ts).
import psalm130 from '../../content/devotions/psalm-130.json';
import { getDocumentById } from './catechisms';
import type { WorshipStep } from './worship';

/** The four browse axes of the devotions hub (mockup 15a), in row order. */
export type GroundingKind = 'scripture' | 'topic' | 'catechism' | 'season';

export type DevotionGrounding =
  /** A book, chapter, or verse range — `osis` is canonical ("Ps.130",
   * "Ps.130.1-Ps.130.8") for the 15b book/chapter browse; `citation` is the
   * display form ("Psalm 130"), authored alongside it exactly as scripture
   * elements carry both. */
  | { kind: 'scripture'; osis: string; citation: string }
  /** A slug into TOPICS. */
  | { kind: 'topic'; topic: string }
  /** A contentById entry id (docs/DOMAIN.md id grammar), e.g. "WSC-1" —
   * the axis that yields one devotion per catechism question. */
  | { kind: 'catechism'; entryId: string }
  /** A slug into SEASONS plus a 1-based day within it (Advent day 3 of 24). */
  | { kind: 'season'; season: string; day: number };

export interface Devotion {
  slug: string;
  title: string;
  /** One-line hub-card blurb (15a's featured card). */
  summary: string;
  /** The landing page's fuller paragraph — what's inside and why it's
   * grounded this way (15c). */
  description: string;
  grounding: DevotionGrounding;
  /** Fixed, pre-resolved steps — no rotation elements. A devotion is the
   * same liturgy every time it's opened; only the daypart services rotate. */
  steps: WorshipStep[];
}

export interface DevotionTopic {
  slug: string;
  name: string;
}

/** The topic axis (15a's "By Topic" row). Registry lives in code, like
 * CREEDAL_DOCUMENTS — topics are curated vocabulary, not derived data. */
export const TOPICS: DevotionTopic[] = [
  { slug: 'repentance', name: 'Repentance' },
  { slug: 'gratitude', name: 'Gratitude' },
  { slug: 'suffering', name: 'Suffering' },
  { slug: 'anxiety', name: 'Anxiety' },
  { slug: 'vocation', name: 'Vocation' },
];

export interface DevotionSeason {
  slug: string;
  name: string;
  /** How many daily devotions a complete season holds (Advent 24, Lent 40). */
  days: number;
}

/** The season axis (15a's "By Season" row). */
export const SEASONS: DevotionSeason[] = [
  { slug: 'advent', name: 'Advent', days: 24 },
  { slug: 'lent', name: 'Lent', days: 40 },
];

// Add a static import + entry here for each authored devotion, same
// one-line shape as psalm-130.
const DEVOTIONS: Devotion[] = [
  psalm130 as unknown as Devotion,
];

/** The hub's "Featured This Week" pick (15a) — editorial, rotated by hand. */
const FEATURED_SLUG = 'psalm-130';

export const getAllDevotions = (): Devotion[] => DEVOTIONS;

export const getDevotion = (slug: string): Devotion | null => DEVOTIONS
  .find((d) => d.slug === slug) ?? null;

export const getFeaturedDevotion = (): Devotion => {
  const featured = getDevotion(FEATURED_SLUG);
  if (!featured) throw new Error(`featured devotion "${FEATURED_SLUG}" is not in the manifest`);
  return featured;
};

/** One hub row's devotions (15a) — every devotion on one grounding axis. */
export const devotionsGroundedIn = (kind: GroundingKind): Devotion[] => DEVOTIONS
  .filter((d) => d.grounding.kind === kind);

/** What a devotion is grounded in, for the "Grounded in …" line: "Psalm 130",
 * "Repentance", "WSC Q. 1", "Advent · Day 3". The prefix is the screen's. */
export const groundingLabel = (grounding: DevotionGrounding): string => {
  switch (grounding.kind) {
    case 'scripture':
      return grounding.citation;
    case 'topic':
      return TOPICS.find((t) => t.slug === grounding.topic)?.name ?? grounding.topic;
    case 'catechism': {
      const [documentId, ...rest] = grounding.entryId.split('-');
      const doc = getDocumentById(documentId);
      const item = rest[rest.length - 1];
      if (!doc || !item) return grounding.entryId;
      return `${doc.shortName} Q. ${item}`;
    }
    case 'season': {
      const season = SEASONS.find((s) => s.slug === grounding.season);
      return `${season?.name ?? grounding.season} · Day ${grounding.day}`;
    }
    default:
      return '';
  }
};
