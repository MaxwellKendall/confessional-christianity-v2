// The programs domain (PRD §5). A program is an authored, ordered plan; the
// flagship instance is the paced walk through the Westminster Shorter
// Catechism. The session-building and mastery rules here are pure functions
// so they can be pinned by tests independent of Supabase.
import type { MasteryState, ProgramPacingRow, QuestionMasteryRow } from './database.types';

export interface ProgramDefinition {
  slug: string;
  /** loose grouping on /programs (PRD §9): family catechesis, scripture, devotional */
  kind: string;
  title: string;
  /** short landing/browse description — handoff copy */
  description: string;
  /** the catechism the plan traverses */
  catechismId: 'WSC';
  totalQuestions: number;
  estimatedMinutes: number;
}

// The first program (PRD §5.1): question, its own proof-text scripture, and
// an authored prayer — teaching notes explicitly deferred (§5.3).
export const PROGRAMS: ProgramDefinition[] = [
  {
    slug: 'catechizing-shorter-catechism',
    kind: 'Family Catechesis',
    title: 'Westminster Shorter Catechism',
    description:
      'The Westminster Shorter Catechism paired with Scripture, prayer, and '
      + 'progress for family teaching.',
    catechismId: 'WSC',
    totalQuestions: 107,
    estimatedMinutes: 15,
  },
];

export const getProgram = (slug: string): ProgramDefinition | null => PROGRAMS
  .find((p) => p.slug === slug) ?? null;

// ---------------------------------------------------------------------------
// Pacing defaults (PRD §5.4/§12): sane for a first-time user, age-adjusted,
// nothing locked.
// ---------------------------------------------------------------------------
export interface PacingConfig {
  newQuestionsPerSession: number;
  sessionsPerWeek: number;
  reviewDepth: 'recent' | 'rotation' | 'weak_only';
  masteryRule: 'streak' | 'manual' | 'exposures';
  showScriptureEveryTime: boolean;
}

export const defaultPacingForAge = (age: number | null): PacingConfig => ({
  // younger children hold fewer new questions per sitting
  newQuestionsPerSession: age !== null && age < 8 ? 1 : 2,
  sessionsPerWeek: 3,
  reviewDepth: 'rotation',
  masteryRule: 'streak',
  showScriptureEveryTime: true,
});

export const pacingFromRow = (row: ProgramPacingRow | null, age: number | null): PacingConfig => (
  row
    ? {
      newQuestionsPerSession: row.new_questions_per_session,
      sessionsPerWeek: row.sessions_per_week,
      reviewDepth: row.review_depth,
      masteryRule: row.mastery_rule,
      showScriptureEveryTime: row.show_scripture_every_time,
    }
    : defaultPacingForAge(age)
);

// ---------------------------------------------------------------------------
// Mastery (PRD §5.6): a question's state is derived from its mastery row;
// absence of a row means not started.
// ---------------------------------------------------------------------------
export const REVIEW_LIMIT = 4;
export const STREAK_TO_MASTER = 3;
export const EXPOSURES_TO_MASTER = 6;

export const masteryStateFor = (
  row: Pick<QuestionMasteryRow, 'state'> | undefined,
): MasteryState => (row ? row.state as MasteryState : 'not_started');

export interface ReviewMark {
  questionNumber: number;
  recited: boolean;
}

// Applies one session's review mark to a mastery row (pure — the hook
// persists the result). Manual rule never auto-masters; the parent marks it.
export const applyReviewMark = (
  row: Pick<QuestionMasteryRow, 'state' | 'recited_streak' | 'exposures'>,
  recited: boolean,
  rule: PacingConfig['masteryRule'],
): Pick<QuestionMasteryRow, 'state' | 'recited_streak' | 'exposures'> => {
  const exposures = row.exposures + 1;
  const streak = recited ? row.recited_streak + 1 : 0;
  let state = row.state;
  if (state !== 'mastered') {
    if (rule === 'streak' && streak >= STREAK_TO_MASTER) state = 'mastered';
    if (rule === 'exposures' && exposures >= EXPOSURES_TO_MASTER) state = 'mastered';
  }
  return { state, recited_streak: streak, exposures };
};

// ---------------------------------------------------------------------------
// Session building (PRD §5.2): new material, then review, then scripture &
// prayer. Pure function over the assignment position, mastery rows, and
// pacing config.
// ---------------------------------------------------------------------------
export interface SessionPlan {
  /** question numbers introduced this session, in order */
  newQuestions: number[];
  /** previously-learned questions to rehearse this session */
  reviewQuestions: number[];
  /** true when every question in the program is already introduced */
  isComplete: boolean;
}

export const buildSessionPlan = (
  currentQuestion: number,
  totalQuestions: number,
  mastery: QuestionMasteryRow[],
  pacing: PacingConfig,
): SessionPlan => {
  if (currentQuestion > totalQuestions) {
    return { newQuestions: [], reviewQuestions: [], isComplete: true };
  }

  const newQuestions: number[] = [];
  for (
    let q = currentQuestion;
    q < currentQuestion + pacing.newQuestionsPerSession && q <= totalQuestions;
    q += 1
  ) {
    newQuestions.push(q);
  }

  const learned = mastery
    .filter((m) => m.question_number < currentQuestion)
    .sort((a, b) => a.question_number - b.question_number);

  let candidates: QuestionMasteryRow[];
  switch (pacing.reviewDepth) {
    case 'recent':
      // a fixed recent window: the last 5 learned
      candidates = learned.slice(-5);
      break;
    case 'weak_only':
      // only what's still shaky
      candidates = learned.filter((m) => m.state === 'reviewing');
      break;
    case 'rotation':
    default:
      // full rotation: least-recently-reviewed first
      candidates = [...learned].sort((a, b) => (
        (a.last_reviewed_at ?? '').localeCompare(b.last_reviewed_at ?? '')
      ));
      break;
  }

  return {
    newQuestions,
    reviewQuestions: candidates.slice(0, REVIEW_LIMIT).map((m) => m.question_number),
    isComplete: false,
  };
};

// "Next Session · Thursday" (mockup 4d): the next session day implied by
// sessions_per_week, from today.
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export const nextSessionDayName = (sessionsPerWeek: number, from = new Date()): string => {
  const gapDays = Math.max(1, Math.round(7 / Math.max(1, sessionsPerWeek)));
  const next = new Date(from);
  next.setDate(next.getDate() + gapDays);
  return WEEKDAYS[next.getDay()];
};
