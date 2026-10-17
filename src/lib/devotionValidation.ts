// Structural checks for an authored devotion — the contract every
// content/devotions/<slug>.json must meet for the hub, the landing page, and
// the eight-step worship shell to render it without new cases. /admin runs
// these before it saves anything; the test suite runs them over every file
// in the repo, so a hand-edited JSON file is held to the same bar.
import { getDocumentById } from './catechisms';
import type { Devotion, DevotionGrounding } from './devotions';
import { SEASONS, TOPICS } from './devotions';
import type { DevotionSeries } from './devotionSeries';
import { getService, type WorshipElement } from './worship';

/** A devotion's steps are the Family Worship service's eight roles, in the
 * service's order — the shell renders by position, not by name. */
export const DEVOTION_ROLES: string[] = getService('morning', new Date(2026, 0, 1))
  .steps.map((step) => step.role);

export const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export const ELEMENT_TYPES = [
  'scripture', 'prayer', 'song', 'creed', 'catechism', 'instruction', 'prompts',
] as const satisfies readonly WorshipElement['type'][];

const isRecord = (value: unknown): value is Record<string, unknown> => (
  typeof value === 'object' && value !== null && !Array.isArray(value)
);

const nonEmpty = (value: unknown): value is string => (
  typeof value === 'string' && value.trim().length > 0
);

const validateGrounding = (grounding: unknown, errors: string[]): void => {
  if (!isRecord(grounding)) {
    errors.push('grounding is required');
    return;
  }
  const g = grounding as Partial<DevotionGrounding> & Record<string, unknown>;
  switch (g.kind) {
    case 'scripture':
      if (!nonEmpty(g.citation)) errors.push('grounding.citation is required');
      if (!nonEmpty(g.osis)) errors.push('grounding.osis is required');
      return;
    case 'topic':
      if (!TOPICS.some((t) => t.slug === g.topic)) {
        errors.push(`grounding.topic must be one of: ${TOPICS.map((t) => t.slug).join(', ')}`);
      }
      return;
    case 'catechism': {
      const ids = g.entryIds;
      if (!Array.isArray(ids) || ids.length === 0) {
        errors.push('grounding.entryIds needs at least one entry id (e.g. WSC-1)');
        return;
      }
      ids.forEach((id, i) => {
        const documentId = typeof id === 'string' ? id.split('-')[0] : '';
        if (typeof id !== 'string' || !/^[A-Za-z0-9]+-\S+$/.test(id) || !getDocumentById(documentId)) {
          errors.push(`grounding.entryIds[${i}] "${String(id)}" is not a known document entry id`);
        }
      });
      const documents = new Set(ids.map((id) => String(id).split('-')[0]));
      if (documents.size > 1) errors.push('grounding.entryIds must all come from one document');
      return;
    }
    case 'season': {
      const season = SEASONS.find((s) => s.slug === g.season);
      if (!season) {
        errors.push(`grounding.season must be one of: ${SEASONS.map((s) => s.slug).join(', ')}`);
        return;
      }
      if (typeof g.day !== 'number' || !Number.isInteger(g.day) || g.day < 1 || g.day > season.days) {
        errors.push(`grounding.day must be a whole number from 1 to ${season.days}`);
      }
      return;
    }
    default:
      errors.push('grounding.kind must be scripture, topic, catechism, or season');
  }
};

const validateElement = (element: unknown, at: string, errors: string[]): void => {
  if (!isRecord(element)) {
    errors.push(`${at} is not an element`);
    return;
  }
  const required = (field: string) => {
    if (!nonEmpty(element[field])) errors.push(`${at}.${field} is required`);
  };
  switch (element.type) {
    case 'scripture':
      required('citation');
      required('osis');
      required('text');
      break;
    case 'prayer':
    case 'instruction':
      required('text');
      break;
    case 'song':
      required('title');
      required('lyrics');
      break;
    case 'creed':
      required('title');
      required('text');
      break;
    case 'catechism':
      break;
    case 'prompts': {
      const items = element.items;
      if (!Array.isArray(items) || items.length === 0) {
        errors.push(`${at}.items needs at least one prompt`);
        break;
      }
      items.forEach((item, i) => {
        if (!isRecord(item) || !nonEmpty(item.label) || !nonEmpty(item.text)) {
          errors.push(`${at}.items[${i}] needs a label and text`);
        }
      });
      break;
    }
    default:
      errors.push(`${at}.type must be one of: ${ELEMENT_TYPES.join(', ')}`);
  }
  if (element.lede !== undefined && typeof element.lede !== 'string') {
    errors.push(`${at}.lede must be text`);
  }
  if (element.source !== undefined) {
    const source = element.source;
    if (!isRecord(source) || !nonEmpty(source.label) || !nonEmpty(source.href)) {
      errors.push(`${at}.source needs a label and a link`);
    }
  }
};

/** Every problem with a would-be devotion, as readable "field: problem"
 * lines; an empty list means it's safe to save. `takenSlugs` are series
 * slugs (and, for a new devotion, existing devotion slugs) — devotions and
 * series share the /devotions/[slug] namespace. */
export const validateDevotion = (
  candidate: unknown,
  { takenSlugs = [] }: { takenSlugs?: string[] } = {},
): string[] => {
  const errors: string[] = [];
  if (!isRecord(candidate)) return ['a devotion must be an object'];
  const d = candidate as Partial<Devotion> & Record<string, unknown>;

  if (!nonEmpty(d.slug) || !SLUG_PATTERN.test(d.slug)) {
    errors.push('slug must be lowercase letters, numbers, and single hyphens (e.g. psalm-23)');
  } else if (takenSlugs.includes(d.slug)) {
    errors.push(`slug "${d.slug}" is already taken`);
  }
  if (!nonEmpty(d.title)) errors.push('title is required');
  if (!nonEmpty(d.summary)) errors.push('summary is required');
  if (!nonEmpty(d.description)) errors.push('description is required');
  validateGrounding(d.grounding, errors);

  if (!Array.isArray(d.steps)) {
    errors.push('steps are required');
    return errors;
  }
  const roles = d.steps.map((step) => (isRecord(step) ? step.role : undefined));
  if (roles.length !== DEVOTION_ROLES.length || roles.some((role, i) => role !== DEVOTION_ROLES[i])) {
    errors.push(`steps must be the eight service roles in order: ${DEVOTION_ROLES.join(' → ')}`);
  }
  d.steps.forEach((step, i) => {
    const label = isRecord(step) && typeof step.role === 'string' ? step.role : `steps[${i}]`;
    if (!isRecord(step) || !Array.isArray(step.elements) || step.elements.length === 0) {
      errors.push(`${label} needs at least one element`);
      return;
    }
    step.elements.forEach((element, j) => validateElement(element, `${label} › element ${j + 1}`, errors));
  });
  return errors;
};

/** Every problem with a series manifest, in the same "field: problem"
 * form as validateDevotion. `otherSeries` are the rest of the library: two
 * series on one season or catechism would make seriesForSeason /
 * seriesForCatechism (and the hub rows built on them) ambiguous. */
export const validateSeries = (
  candidate: unknown,
  { takenSlugs = [], otherSeries = [] }: { takenSlugs?: string[]; otherSeries?: DevotionSeries[] } = {},
): string[] => {
  if (!isRecord(candidate)) return ['a series must be an object'];
  const series = candidate as Partial<DevotionSeries> & Record<string, unknown>;
  const errors: string[] = [];

  if (!nonEmpty(series.slug) || !SLUG_PATTERN.test(series.slug)) {
    errors.push('slug must be lowercase letters, numbers, and single hyphens (e.g. lent)');
  } else if (takenSlugs.includes(series.slug)) {
    errors.push(`slug "${series.slug}" is already taken`);
  }
  if (!nonEmpty(series.title)) errors.push('title is required');
  if (!nonEmpty(series.tagline)) errors.push('tagline is required');
  if (!nonEmpty(series.description)) errors.push('description is required');

  const source: Record<string, unknown> = isRecord(series.source) ? series.source : {};
  if (source.kind === 'season') {
    const season = SEASONS.find((s) => s.slug === source.season);
    if (!season) errors.push(`source.season must be one of: ${SEASONS.map((s) => s.slug).join(', ')}`);
    else if (Array.isArray(series.parts) && series.parts.length > season.days) {
      errors.push(`${season.name} has ${season.days} days, so its series can't have ${series.parts.length} parts`);
    }
  } else if (source.kind === 'catechism') {
    if (typeof source.documentId !== 'string' || !getDocumentById(source.documentId)) {
      errors.push('source.documentId must be a known document (e.g. WSC)');
    }
  } else {
    errors.push('source.kind must be season or catechism');
  }
  const clash = otherSeries.find((other) => other.slug !== series.slug
    && other.source.kind === source.kind
    && (other.source.kind === 'season'
      ? other.source.season === source.season
      : other.source.documentId === source.documentId));
  if (clash) errors.push(`"${clash.title}" (${clash.slug}) already covers this ${source.kind}`);

  if (!Array.isArray(series.parts) || series.parts.length === 0) {
    errors.push('a series needs at least one part');
    return errors;
  }
  series.parts.forEach((part, i) => {
    if (!isRecord(part)) {
      errors.push(`part ${i + 1} is not a part`);
      return;
    }
    if (part.day !== i + 1) errors.push(`part ${i + 1} has day ${String(part.day)}`);
    if (!nonEmpty(part.title)) errors.push(`part ${i + 1} needs a title`);
    if (!nonEmpty(part.citation)) errors.push(`part ${i + 1} needs a citation`);
  });
  const linked = series.parts.flatMap((p) => (isRecord(p) && typeof p.devotionSlug === 'string' ? [p.devotionSlug] : []));
  if (new Set(linked).size !== linked.length) errors.push('one devotion is linked to two parts');
  return errors;
};

/** Folds an edited series onto the stored ones before it is written:
 *
 * - devotion links come from `current` (the file the save builds on), by
 *   day — they're owned by each devotion's editor, never by this form;
 * - parts in `published` (what households have) can be retitled but never
 *   removed, because series progress is stored by day number on devices.
 *
 * Throws when the edit drops a published part. */
export const mergeSeriesEdit = (
  draft: DevotionSeries,
  current: DevotionSeries | null,
  published: DevotionSeries | null,
): DevotionSeries => {
  if (published && draft.parts.length < published.parts.length) {
    throw new Error(`${published.title} is published with ${published.parts.length} parts; parts can be added but not removed`);
  }
  const lastLinked = Math.max(0, ...(current?.parts ?? []).filter((p) => p.devotionSlug).map((p) => p.day));
  if (draft.parts.length < lastLinked) {
    throw new Error(`part ${lastLinked} has a devotion linked; unlink it from that devotion before removing the part`);
  }
  return {
    ...draft,
    parts: draft.parts.map((part, i) => {
      const day = i + 1;
      const rest = { ...part };
      delete rest.devotionSlug;
      const link = current?.parts.find((p) => p.day === day)?.devotionSlug;
      return link ? { ...rest, day, devotionSlug: link } : { ...rest, day };
    }),
  };
};

export interface SeriesLink {
  seriesSlug: string;
  day: number;
}

/** Where a devotion sits in the series manifests, if anywhere. */
export const findSeriesLink = (allSeries: DevotionSeries[], slug: string): SeriesLink | null => {
  for (const series of allSeries) {
    const part = series.parts.find((p) => p.devotionSlug === slug);
    if (part) return { seriesSlug: series.slug, day: part.day };
  }
  return null;
};

/** Points the series manifests at `slug` as `link` describes (or unlinks it
 * everywhere when `link` is null), returning only the series whose JSON
 * actually changed. Throws when the target part already carries a different
 * devotion — replacing another author's part is a deliberate unlink first,
 * never a side effect of saving. */
export const relinkSeries = (
  allSeries: DevotionSeries[],
  slug: string,
  link: SeriesLink | null,
): DevotionSeries[] => {
  if (link) {
    const target = allSeries.find((s) => s.slug === link.seriesSlug);
    if (!target) throw new Error(`series "${link.seriesSlug}" does not exist`);
    const part = target.parts.find((p) => p.day === link.day);
    if (!part) throw new Error(`series "${link.seriesSlug}" has no part ${link.day}`);
    if (part.devotionSlug && part.devotionSlug !== slug) {
      throw new Error(`${target.title} part ${link.day} already belongs to "${part.devotionSlug}"`);
    }
  }
  const changed: DevotionSeries[] = [];
  for (const series of allSeries) {
    let dirty = false;
    const parts = series.parts.map((part) => {
      const shouldLink = link?.seriesSlug === series.slug && link.day === part.day;
      if (shouldLink && part.devotionSlug !== slug) {
        dirty = true;
        return { ...part, devotionSlug: slug };
      }
      if (!shouldLink && part.devotionSlug === slug) {
        dirty = true;
        const rest = { ...part };
        delete rest.devotionSlug;
        return rest;
      }
      return part;
    });
    if (dirty) changed.push({ ...series, parts });
  }
  return changed;
};

const isLeafObject = (value: object): boolean => !Array.isArray(value)
  && Object.values(value).every((v) => v === null || typeof v !== 'object');

const inlineJson = (value: unknown): string => {
  if (Array.isArray(value)) return `[${value.map(inlineJson).join(', ')}]`;
  if (value && typeof value === 'object') {
    return `{ ${Object.entries(value).map(([k, v]) => `${JSON.stringify(k)}: ${inlineJson(v)}`).join(', ')} }`;
  }
  return JSON.stringify(value);
};

/** Two-space JSON that keeps all-primitive objects (a grounding, a series
 * part) on one line when the line stays within `width`. */
const formatJson = (value: unknown, width: number, indent = '', prefix = ''): string => {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  const oneLine = inlineJson(value);
  if (isLeafObject(value) && indent.length + prefix.length + oneLine.length + 1 <= width) return oneLine;
  const inner = `${indent}  `;
  if (Array.isArray(value)) {
    return value.length
      ? `[\n${value.map((v) => inner + formatJson(v, width, inner)).join(',\n')}\n${indent}]`
      : '[]';
  }
  const entries = Object.entries(value);
  if (!entries.length) return '{}';
  return `{\n${entries.map(([k, v]) => {
    const key = `${JSON.stringify(k)}: `;
    return `${inner}${key}${formatJson(v, width, inner, key)}`;
  }).join(',\n')}\n${indent}}`;
};

// The layouts the hand-authored files use: fully expanded (the generated
// WSC run), leaf objects inlined within 80 columns (the Advent devotions),
// and leaf objects always inlined (the Advent series' one-line parts).
const LAYOUT_WIDTHS = [0, 80, Number.POSITIVE_INFINITY];

/** The on-disk JSON for a devotion or series, trailing newline included.
 * Given the file's current text, it keeps whichever layout that file was
 * written in, so an admin save diffs only the fields that changed; new
 * files (and files in no known layout) come out fully expanded. */
export const toContentJson = (value: unknown, original?: string | null): string => {
  if (original) {
    try {
      const before = JSON.parse(original) as unknown;
      const width = LAYOUT_WIDTHS.find((w) => `${formatJson(before, w)}\n` === original);
      if (width !== undefined) return `${formatJson(value, width)}\n`;
    } catch {
      // unreadable original: fall through to the default layout
    }
  }
  return `${formatJson(value, 0)}\n`;
};
