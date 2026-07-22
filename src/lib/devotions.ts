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
import advent1 from '../../content/devotions/advent-1.json';
import advent2 from '../../content/devotions/advent-2.json';
import advent3 from '../../content/devotions/advent-3.json';
import psalm130 from '../../content/devotions/psalm-130.json';
import wsc1 from '../../content/devotions/wsc-1.json';
import wsc2 from '../../content/devotions/wsc-2.json';
import wsc3 from '../../content/devotions/wsc-3.json';
import wsc4 from '../../content/devotions/wsc-4.json';
import wsc5 from '../../content/devotions/wsc-5.json';
import wsc6 from '../../content/devotions/wsc-6.json';
import wsc7 from '../../content/devotions/wsc-7.json';
import wsc8 from '../../content/devotions/wsc-8.json';
import wsc9 from '../../content/devotions/wsc-9.json';
import wsc10 from '../../content/devotions/wsc-10.json';
import wsc11 from '../../content/devotions/wsc-11.json';
import wsc12 from '../../content/devotions/wsc-12.json';
import wsc13 from '../../content/devotions/wsc-13.json';
import wsc14 from '../../content/devotions/wsc-14.json';
import wsc15 from '../../content/devotions/wsc-15.json';
import wsc16 from '../../content/devotions/wsc-16.json';
import wsc17 from '../../content/devotions/wsc-17.json';
import wsc18 from '../../content/devotions/wsc-18.json';
import wsc19 from '../../content/devotions/wsc-19.json';
import wsc20 from '../../content/devotions/wsc-20.json';
import wsc21 from '../../content/devotions/wsc-21.json';
import wsc22 from '../../content/devotions/wsc-22.json';
import wsc23 from '../../content/devotions/wsc-23.json';
import wsc24 from '../../content/devotions/wsc-24.json';
import wsc25 from '../../content/devotions/wsc-25.json';
import wsc26 from '../../content/devotions/wsc-26.json';
import wsc27 from '../../content/devotions/wsc-27.json';
import wsc28 from '../../content/devotions/wsc-28.json';
import wsc29 from '../../content/devotions/wsc-29.json';
import wsc30 from '../../content/devotions/wsc-30.json';
import wsc31 from '../../content/devotions/wsc-31.json';
import wsc32 from '../../content/devotions/wsc-32.json';
import wsc33 from '../../content/devotions/wsc-33.json';
import wsc34 from '../../content/devotions/wsc-34.json';
import wsc35 from '../../content/devotions/wsc-35.json';
import wsc36 from '../../content/devotions/wsc-36.json';
import wsc37 from '../../content/devotions/wsc-37.json';
import wsc38 from '../../content/devotions/wsc-38.json';
import wsc39 from '../../content/devotions/wsc-39.json';
import wsc40 from '../../content/devotions/wsc-40.json';
import wsc42 from '../../content/devotions/wsc-42.json';
import wsc43 from '../../content/devotions/wsc-43.json';
import wsc45 from '../../content/devotions/wsc-45.json';
import wsc47 from '../../content/devotions/wsc-47.json';
import wsc49 from '../../content/devotions/wsc-49.json';
import wsc51 from '../../content/devotions/wsc-51.json';
import wsc53 from '../../content/devotions/wsc-53.json';
import wsc55 from '../../content/devotions/wsc-55.json';
import wsc57 from '../../content/devotions/wsc-57.json';
import wsc59 from '../../content/devotions/wsc-59.json';
import wsc61 from '../../content/devotions/wsc-61.json';
import wsc63 from '../../content/devotions/wsc-63.json';
import wsc65 from '../../content/devotions/wsc-65.json';
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
  /** contentById entry ids (docs/DOMAIN.md id grammar), e.g. ["WSC-1"] —
   * the axis that yields one devotion per catechism question. Occasionally
   * two consecutive questions are professed in one devotion, hence an array
   * rather than a single id. */
  | { kind: 'catechism'; entryIds: string[] }
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
  advent1 as unknown as Devotion,
  advent2 as unknown as Devotion,
  advent3 as unknown as Devotion,
  wsc1 as unknown as Devotion,
  wsc2 as unknown as Devotion,
  wsc3 as unknown as Devotion,
  wsc4 as unknown as Devotion,
  wsc5 as unknown as Devotion,
  wsc6 as unknown as Devotion,
  wsc7 as unknown as Devotion,
  wsc8 as unknown as Devotion,
  wsc9 as unknown as Devotion,
  wsc10 as unknown as Devotion,
  wsc11 as unknown as Devotion,
  wsc12 as unknown as Devotion,
  wsc13 as unknown as Devotion,
  wsc14 as unknown as Devotion,
  wsc15 as unknown as Devotion,
  wsc16 as unknown as Devotion,
  wsc17 as unknown as Devotion,
  wsc18 as unknown as Devotion,
  wsc19 as unknown as Devotion,
  wsc20 as unknown as Devotion,
  wsc21 as unknown as Devotion,
  wsc22 as unknown as Devotion,
  wsc23 as unknown as Devotion,
  wsc24 as unknown as Devotion,
  wsc25 as unknown as Devotion,
  wsc26 as unknown as Devotion,
  wsc27 as unknown as Devotion,
  wsc28 as unknown as Devotion,
  wsc29 as unknown as Devotion,
  wsc30 as unknown as Devotion,
  wsc31 as unknown as Devotion,
  wsc32 as unknown as Devotion,
  wsc33 as unknown as Devotion,
  wsc34 as unknown as Devotion,
  wsc35 as unknown as Devotion,
  wsc36 as unknown as Devotion,
  wsc37 as unknown as Devotion,
  wsc38 as unknown as Devotion,
  wsc39 as unknown as Devotion,
  wsc40 as unknown as Devotion,
  wsc42 as unknown as Devotion,
  wsc43 as unknown as Devotion,
  wsc45 as unknown as Devotion,
  wsc47 as unknown as Devotion,
  wsc49 as unknown as Devotion,
  wsc51 as unknown as Devotion,
  wsc53 as unknown as Devotion,
  wsc55 as unknown as Devotion,
  wsc57 as unknown as Devotion,
  wsc59 as unknown as Devotion,
  wsc61 as unknown as Devotion,
  wsc63 as unknown as Devotion,
  wsc65 as unknown as Devotion,
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

/** The OSIS book id a scripture-grounded devotion lives in ("Ps.130.1-Ps.130.8"
 * → "Ps"), keying the 15b book browse; null on every other axis. */
export const groundingBookOsis = (grounding: DevotionGrounding): string | null => (
  grounding.kind === 'scripture' ? grounding.osis.split(/[.-]/)[0] : null
);

/** The chapter a scripture grounding starts in ("Ps.130" → 130) — the 15b
 * range-chip label; null when the osis is book-level or the axis differs. */
export const groundingChapter = (grounding: DevotionGrounding): number | null => {
  if (grounding.kind !== 'scripture') return null;
  const chapter = Number(grounding.osis.split('-')[0].split('.')[1]);
  return Number.isInteger(chapter) ? chapter : null;
};

/** Scripture-grounded devotions per OSIS book, each book's list in chapter
 * order — the 15b "choose a range" sections. */
export const scriptureDevotionsByBook = (): Map<string, Devotion[]> => {
  const byBook = new Map<string, Devotion[]>();
  for (const devotion of devotionsGroundedIn('scripture')) {
    const book = groundingBookOsis(devotion.grounding);
    if (!book) continue;
    const list = byBook.get(book) ?? [];
    list.push(devotion);
    byBook.set(book, list);
  }
  for (const list of byBook.values()) {
    list.sort((a, b) => (groundingChapter(a.grounding) ?? 0) - (groundingChapter(b.grounding) ?? 0));
  }
  return byBook;
};

/** What a devotion is grounded in, for the "Grounded in …" line: "Psalm 130",
 * "Repentance", "WSC Q. 1", "Advent · Day 3". The prefix is the screen's. */
export const groundingLabel = (grounding: DevotionGrounding): string => {
  switch (grounding.kind) {
    case 'scripture':
      return grounding.citation;
    case 'topic':
      return TOPICS.find((t) => t.slug === grounding.topic)?.name ?? grounding.topic;
    case 'catechism': {
      const [documentId] = grounding.entryIds[0].split('-');
      const doc = getDocumentById(documentId);
      const items = grounding.entryIds.map((id) => id.slice(documentId.length + 1));
      if (!doc || items.some((item) => !item)) return grounding.entryIds.join(', ');
      return items.length === 1
        ? `${doc.shortName} Q. ${items[0]}`
        : `${doc.shortName} Q. ${items[0]}–${items[items.length - 1]}`;
    }
    case 'season': {
      const season = SEASONS.find((s) => s.slug === grounding.season);
      return `${season?.name ?? grounding.season} · Day ${grounding.day}`;
    }
    default:
      return '';
  }
};
