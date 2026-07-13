// The programs domain (PRD §5). A program is an authored, ordered walk
// through a catechism.
import type { ContentId } from './programContent';

export interface ProgramDefinition {
  slug: string;
  /** loose grouping on /programs (PRD §9): family catechesis, scripture, devotional */
  kind: string;
  title: string;
  /** conversational short name used in CTAs ("Continue the {shortTitle}") */
  shortTitle: string;
  /** confessional tradition shown as the landing eyebrow; omit when the
   * document belongs to no standard grouping */
  tradition?: string;
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
    shortTitle: 'Shorter Catechism',
    tradition: 'Westminster Standards',
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
    shortTitle: 'Catechism for Young Children',
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
    shortTitle: 'Larger Catechism',
    tradition: 'Westminster Standards',
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
    shortTitle: 'Heidelberg Catechism',
    tradition: 'Three Forms of Unity',
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
