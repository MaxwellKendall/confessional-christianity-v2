// Family Worship (turn 11): a guided order of service, morning and evening.
// The liturgy is data — an ordered list of typed elements (scripture, prayer,
// song, creed, prompts, and one catechism hand-off) — so the eight step
// screens are a single renderer and the AM/PM services are two JSON files,
// not two flows. Scripture here is historic public-domain text authored in
// the content files (the canvas's "Sourcing" note), never fetched.
// Statically imported so the bundler traces the data — a dynamic fs read
// breaks in Vercel's serverless bundles (see programContent.ts).
import morningJson from '../../content/worship/morning.json';
import eveningJson from '../../content/worship/evening.json';

export type Daypart = 'morning' | 'evening';

/** Where an element points beyond its own text — a recording of the song, the
 * book a prayer originates in. Informational detours only, never required. */
export interface ElementSource {
  label: string;
  href: string;
  /** true renders ↗ (leaves the app); false/absent renders › (stays in it). */
  external?: boolean;
}

export type WorshipElement = { lede?: string; source?: ElementSource } & (
  | { type: 'scripture'; citation: string; osis: string; text: string }
  | { type: 'prayer'; text: string; amen?: boolean }
  | { type: 'song'; title: string; lyrics: string }
  | { type: 'creed'; title: string; text: string }
  | { type: 'catechism' }
  | { type: 'instruction'; text: string }
  | { type: 'prompts'; items: { label: string; text: string }[] }
);

/** An element position whose content rotates by day — the daily psalm, the
 * reading, the song. Fixed sibling elements stay fixed. */
type RotationElement = { type: 'rotation'; options: WorshipElement[] };

interface LiturgyStepJson {
  role: string;
  elements: (WorshipElement | RotationElement)[];
}

export interface WorshipStep {
  role: string;
  elements: WorshipElement[];
}

export interface WorshipService {
  daypart: Daypart;
  steps: WorshipStep[];
}

const LITURGIES: Record<Daypart, LiturgyStepJson[]> = {
  morning: morningJson as unknown as LiturgyStepJson[],
  evening: eveningJson as unknown as LiturgyStepJson[],
};

/** Whole days since the epoch for a local calendar date — the deterministic
 * index rotating slots key off, so the whole household sees one service per
 * day regardless of the hour they gather. */
export const dayIndexOf = (date: Date): number => Math.floor(
  Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000,
);

const resolveElement = (
  element: WorshipElement | RotationElement,
  dayIndex: number,
): WorshipElement | null => {
  if (element.type !== 'rotation') return element;
  if (element.options.length === 0) return null;
  return element.options[dayIndex % element.options.length];
};

/** The concrete service for one daypart on one date, rotations resolved. */
export const getService = (daypart: Daypart, date: Date): WorshipService => {
  const dayIndex = dayIndexOf(date);
  return {
    daypart,
    steps: LITURGIES[daypart].map((step) => ({
      role: step.role,
      elements: step.elements
        .map((element) => resolveElement(element, dayIndex))
        .filter((element): element is WorshipElement => element !== null),
    })),
  };
};

/** The order-preview detail line for a step (mockup 11a): what's named after
 * the em-dash, e.g. "Call to Worship — Psalm 100:2". Null when the role
 * stands alone; the catechism step's question detail is the caller's to fill
 * (it depends on the child's track, not the liturgy). */
export const stepDetail = (step: WorshipStep): string | null => {
  const lead = step.elements[0];
  if (!lead) return null;
  if (lead.type === 'scripture') return lead.citation;
  if (lead.type === 'song') return lead.title;
  if (lead.type === 'creed') return lead.title;
  return null;
};
