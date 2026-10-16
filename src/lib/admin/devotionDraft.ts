// Starting points for the /admin editor — client-safe (no fs, no secrets).
import type { Devotion } from '../devotions';
import { DEVOTION_ROLES } from '../devotionValidation';
import type { WorshipElement } from '../worship';

export type ElementType = WorshipElement['type'];

/** An empty element of `type`, with every required field present. */
export const blankElement = (type: ElementType): WorshipElement => {
  switch (type) {
    case 'scripture': return { type, citation: '', osis: '', text: '' };
    case 'prayer': return { type, text: '' };
    case 'song': return { type, title: '', lyrics: '' };
    case 'creed': return { type, title: '', text: '' };
    case 'catechism': return { type };
    case 'instruction': return { type, text: '' };
    case 'prompts': return { type, items: [{ label: '', text: '' }] };
    default: throw new Error(`unknown element type ${String(type)}`);
  }
};

/** What each step usually opens with across the authored devotions. */
const DEFAULT_TYPES: Record<string, ElementType[]> = {
  'Call to Worship': ['scripture'],
  'Confessing Sin': ['prayer'],
  'Receiving Forgiveness': ['scripture'],
  'Singing Praise': ['song'],
  'Professing Faith': ['catechism'],
  'Reading Scripture': ['scripture', 'instruction'],
  'Making Requests': ['prompts'],
  'Closing Prayer': ['prayer'],
};

export const blankDevotion = (): Devotion => ({
  slug: '',
  title: '',
  summary: '',
  description: '',
  grounding: { kind: 'scripture', osis: '', citation: '' },
  steps: DEVOTION_ROLES.map((role) => ({
    role,
    elements: (DEFAULT_TYPES[role] ?? ['prayer']).map(blankElement),
  })),
});

/** A new devotion that reuses another's liturgy — the shared prayers and
 * songs most devotions carry — with its identity cleared for the author. */
export const devotionFrom = (template: Devotion): Devotion => ({
  ...structuredClone(template),
  slug: '',
  title: '',
  summary: '',
  description: '',
});
