// The programs domain (PRD §5). A program is an authored, ordered walk
// through a catechism.
import type { ContentId } from './programContent';
import type { MasteryState, QuestionMasteryRow } from './database.types';

export interface ProgramDefinition {
  slug: string;
  /** loose grouping on /programs (PRD §9): family catechesis, scripture, devotional */
  kind: string;
  title: string;
  /** short landing/browse description — handoff copy */
  description: string;
  /** the catechism the program traverses */
  contentId: ContentId;
  totalQuestions: number;
  estimatedMinutes: number;
}

// Question, its own proof-text scripture, and an authored prayer — teaching
// notes explicitly deferred (§5.3).
export const PROGRAMS: ProgramDefinition[] = [
  {
    slug: 'catechizing-shorter-catechism',
    kind: 'Family Catechesis',
    title: 'Westminster Shorter Catechism',
    description:
      'The Westminster Shorter Catechism paired with Scripture, prayer, and '
      + 'progress for family teaching.',
    contentId: 'WSC',
    totalQuestions: 107,
    estimatedMinutes: 15,
  },
  {
    slug: 'catechism-for-young-children',
    kind: 'Family Catechesis',
    title: 'Catechism for Young Children',
    description:
      'A simple, memorable introduction to the faith for the youngest learners.',
    contentId: 'CFYC',
    totalQuestions: 145,
    estimatedMinutes: 10,
  },
  {
    slug: 'catechizing-larger-catechism',
    kind: 'Family Catechesis',
    title: 'Westminster Larger Catechism',
    description:
      'A more comprehensive walk through the Westminster Larger Catechism, '
      + 'paired with Scripture, prayer, and progress.',
    contentId: 'WLC',
    totalQuestions: 196,
    estimatedMinutes: 20,
  },
  {
    slug: 'catechizing-heidelberg-catechism',
    kind: 'Family Catechesis',
    title: 'Heidelberg Catechism',
    description:
      'The Heidelberg Catechism paired with Scripture, prayer, and progress '
      + 'for family teaching.',
    contentId: 'HC',
    totalQuestions: 129,
    estimatedMinutes: 15,
  },
];

export const getProgram = (slug: string): ProgramDefinition | null => PROGRAMS
  .find((p) => p.slug === slug) ?? null;

// ---------------------------------------------------------------------------
// Mastery (PRD §5.6): a question's state is derived from its mastery row;
// absence of a row means not started. There's no pacing/scheduling anymore
// (turn 9) — a question becomes "seen" the moment a session advances past
// it, and mastery is a manual parent toggle (ProgramLandingClient's Heart).
// ---------------------------------------------------------------------------
export const masteryStateFor = (
  row: Pick<QuestionMasteryRow, 'state'> | undefined,
): MasteryState => (row ? row.state as MasteryState : 'not_started');
