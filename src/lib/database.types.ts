// Hand-authored types for the existing Supabase schema (supabase/migrations/).
// The v2 app points at the same live project as v1 — account and progress
// data survives the rewrite — so these mirror the deployed tables exactly,
// plus the additive programs-domain columns from the v2 migrations.

export type GuardianRole = 'owner' | 'guardian';

/** Per-question mastery states (PRD §5.6). */
export type MasteryState = 'not_started' | 'reviewing' | 'mastered';

export interface ChildRow {
  id: string;
  user_id: string;
  name: string;
  birth_date: string | null;
  /** Added by the v2 programs migration; age drives pacing defaults (PRD §12). */
  age: number | null;
  created_at: string;
  updated_at: string;
}

export interface UserChildRow {
  id: string;
  user_id: string;
  child_id: string;
  role: GuardianRole;
  created_at: string;
}

export interface CatechismAssignmentRow {
  id: string;
  child_id: string;
  catechism_id: string;
  current_question: number;
  started_at: string;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface ChildShareInviteRow {
  id: string;
  child_id: string;
  invited_by: string;
  invite_code: string;
  invited_email: string | null;
  accepted_by: string | null;
  accepted_at: string | null;
  expires_at: string;
  created_at: string;
}

export interface UserCatechismAssignmentRow {
  id: string;
  user_id: string;
  catechism_id: string;
  current_question: number;
  started_at: string;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
}

/** v2 programs domain: per-assignment pacing configuration (PRD §5.4). */
export interface ProgramPacingRow {
  id: string;
  assignment_id: string;
  new_questions_per_session: number;
  sessions_per_week: number;
  review_depth: 'recent' | 'rotation' | 'weak_only';
  mastery_rule: 'streak' | 'manual' | 'exposures';
  show_scripture_every_time: boolean;
  created_at: string;
  updated_at: string;
}

/** v2 programs domain: per-question mastery tracking (PRD §5.6). */
export interface QuestionMasteryRow {
  id: string;
  assignment_id: string;
  question_number: number;
  state: MasteryState;
  recited_streak: number;
  exposures: number;
  last_reviewed_at: string | null;
  created_at: string;
  updated_at: string;
}

/** A child together with the viewing user's relationship to it. */
export interface ChildWithRole extends ChildRow {
  userRole: GuardianRole;
  isOwner: boolean;
  catechism_assignments: CatechismAssignmentRow[];
}
