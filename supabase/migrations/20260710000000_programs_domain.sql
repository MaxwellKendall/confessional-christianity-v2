-- v2 programs domain (PRD §5): additive only — the same live Supabase project
-- keeps serving v1 untouched while these land.
--
-- children.age: PRD §12 — age (not birthdate) drives pacing defaults. The
-- existing birth_date column is left in place for live rows.
ALTER TABLE children ADD COLUMN IF NOT EXISTS age INTEGER;

-- ============================================================================
-- program_pacing: the household's configuration for one program run
-- (one catechism_assignment), per PRD §5.4. Defaults are the mockup 2e values.
-- ============================================================================
CREATE TABLE IF NOT EXISTS program_pacing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id UUID NOT NULL REFERENCES catechism_assignments(id) ON DELETE CASCADE,
  new_questions_per_session INTEGER NOT NULL DEFAULT 2 CHECK (new_questions_per_session BETWEEN 1 AND 10),
  sessions_per_week INTEGER NOT NULL DEFAULT 3 CHECK (sessions_per_week BETWEEN 1 AND 7),
  review_depth TEXT NOT NULL DEFAULT 'rotation' CHECK (review_depth IN ('recent', 'rotation', 'weak_only')),
  mastery_rule TEXT NOT NULL DEFAULT 'streak' CHECK (mastery_rule IN ('streak', 'manual', 'exposures')),
  show_scripture_every_time BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(assignment_id)
);

CREATE INDEX IF NOT EXISTS program_pacing_assignment_id_idx ON program_pacing(assignment_id);
ALTER TABLE program_pacing ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- question_mastery: per-question state for one program run (PRD §5.6).
-- A row exists once a question has been introduced; absence = not started.
-- ============================================================================
CREATE TABLE IF NOT EXISTS question_mastery (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id UUID NOT NULL REFERENCES catechism_assignments(id) ON DELETE CASCADE,
  question_number INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'reviewing' CHECK (state IN ('reviewing', 'mastered')),
  recited_streak INTEGER NOT NULL DEFAULT 0,
  exposures INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
  UNIQUE(assignment_id, question_number)
);

CREATE INDEX IF NOT EXISTS question_mastery_assignment_id_idx ON question_mastery(assignment_id);
ALTER TABLE question_mastery ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS: access follows the assignment -> child -> user_children chain, the
-- same shape as catechism_assignments' own policies.
-- ============================================================================
CREATE POLICY "Guardians can view pacing" ON program_pacing
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = program_pacing.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can insert pacing" ON program_pacing
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = program_pacing.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can update pacing" ON program_pacing
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = program_pacing.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can delete pacing" ON program_pacing
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = program_pacing.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can view mastery" ON question_mastery
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = question_mastery.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can insert mastery" ON question_mastery
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = question_mastery.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can update mastery" ON question_mastery
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = question_mastery.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

CREATE POLICY "Guardians can delete mastery" ON question_mastery
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM catechism_assignments ca
      JOIN user_children uc ON uc.child_id = ca.child_id
      WHERE ca.id = question_mastery.assignment_id
      AND uc.user_id = auth.uid()
    )
  );

-- updated_at triggers (reuses the existing function)
CREATE TRIGGER update_program_pacing_updated_at
  BEFORE UPDATE ON program_pacing
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_question_mastery_updated_at
  BEFORE UPDATE ON question_mastery
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
