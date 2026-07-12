'use client';

// Data access for one child's run of a program: the catechism assignment,
// its pacing config, and per-question mastery. All the decision logic lives
// in src/lib/programs.ts (pure, tested); this hook only moves rows.
import { useCallback, useEffect, useState } from 'react';

import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import {
  applyReviewMark,
  defaultPacingForAge,
  pacingFromRow,
  type PacingConfig,
  type ProgramDefinition,
  type SessionPlan,
} from '@/lib/programs';
import type {
  CatechismAssignmentRow,
  ChildWithRole,
  ProgramPacingRow,
  QuestionMasteryRow,
} from '@/lib/database.types';
import type { ReviewMark } from '@/lib/programs';

export interface ProgramRunState {
  assignment: CatechismAssignmentRow | null;
  pacing: PacingConfig;
  pacingRow: ProgramPacingRow | null;
  mastery: QuestionMasteryRow[];
}

export const useProgramState = (program: ProgramDefinition, child: ChildWithRole | null) => {
  const supabase = getSupabaseBrowserClient();
  const [state, setState] = useState<ProgramRunState>({
    assignment: null,
    pacing: defaultPacingForAge(child?.age ?? null),
    pacingRow: null,
    mastery: [],
  });
  const [loading, setLoading] = useState(true);

  const assignment = child?.catechism_assignments
    ?.find((a) => a.catechism_id === program.catechismId) ?? null;

  const fetchState = useCallback(async () => {
    if (!supabase || !child || !assignment) {
      setState({
        assignment: assignment ?? null,
        pacing: defaultPacingForAge(child?.age ?? null),
        pacingRow: null,
        mastery: [],
      });
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const [pacingRes, masteryRes] = await Promise.all([
        supabase.from('program_pacing').select('*').eq('assignment_id', assignment.id).maybeSingle(),
        supabase.from('question_mastery').select('*').eq('assignment_id', assignment.id),
      ]);
      const pacingRow = (pacingRes.data ?? null) as ProgramPacingRow | null;
      setState({
        assignment,
        pacingRow,
        pacing: pacingFromRow(pacingRow, child.age),
        mastery: (masteryRes.data ?? []) as QuestionMasteryRow[],
      });
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase, child?.id, assignment?.id]);

  useEffect(() => {
    fetchState();
  }, [fetchState]);

  // Starting a program is choosing a child for it (PRD §5.5): one assignment
  // plus its pacing row seeded from the child's age.
  const startProgram = async (targetChild: ChildWithRole, startingQuestion = 1) => {
    if (!supabase) throw new Error('Supabase not configured');
    const { data, error } = await supabase
      .from('catechism_assignments')
      .insert({
        child_id: targetChild.id,
        catechism_id: program.catechismId,
        current_question: startingQuestion,
      })
      .select()
      .single();
    if (error) throw error;
    const created = data as CatechismAssignmentRow;
    const defaults = defaultPacingForAge(targetChild.age);
    await supabase.from('program_pacing').insert({
      assignment_id: created.id,
      new_questions_per_session: defaults.newQuestionsPerSession,
      sessions_per_week: defaults.sessionsPerWeek,
      review_depth: defaults.reviewDepth,
      mastery_rule: defaults.masteryRule,
      show_scripture_every_time: defaults.showScriptureEveryTime,
    });
    return created;
  };

  const savePacing = async (config: PacingConfig) => {
    if (!supabase || !assignment) throw new Error('No program run to configure');
    const row = {
      assignment_id: assignment.id,
      new_questions_per_session: config.newQuestionsPerSession,
      sessions_per_week: config.sessionsPerWeek,
      review_depth: config.reviewDepth,
      mastery_rule: config.masteryRule,
      show_scripture_every_time: config.showScriptureEveryTime,
    };
    const { error } = await supabase
      .from('program_pacing')
      .upsert(row, { onConflict: 'assignment_id' });
    if (error) throw error;
    await fetchState();
  };

  // Persists one finished session: review marks fold into mastery rows, new
  // questions enter rotation, and the assignment position advances.
  const completeSession = async (plan: SessionPlan, marks: ReviewMark[]) => {
    if (!supabase || !assignment) throw new Error('No active program run');
    const now = new Date().toISOString();

    const byNumber = new Map(state.mastery.map((m) => [m.question_number, m]));
    const upserts: Record<string, unknown>[] = [];

    marks.forEach((mark) => {
      const row = byNumber.get(mark.questionNumber);
      const applied = applyReviewMark(
        row ?? { state: 'reviewing', recited_streak: 0, exposures: 0 },
        mark.recited,
        state.pacing.masteryRule,
      );
      upserts.push({
        assignment_id: assignment.id,
        question_number: mark.questionNumber,
        ...applied,
        last_reviewed_at: now,
      });
    });

    plan.newQuestions.forEach((q) => {
      if (byNumber.has(q)) return;
      upserts.push({
        assignment_id: assignment.id,
        question_number: q,
        state: 'reviewing',
        recited_streak: 0,
        exposures: 1,
        last_reviewed_at: now,
      });
    });

    if (upserts.length) {
      const { error } = await supabase
        .from('question_mastery')
        .upsert(upserts, { onConflict: 'assignment_id,question_number' });
      if (error) throw error;
    }

    const nextQuestion = assignment.current_question + plan.newQuestions.length;
    const completed = nextQuestion > program.totalQuestions;
    const { error: updateError } = await supabase
      .from('catechism_assignments')
      .update({
        current_question: nextQuestion,
        ...(completed ? { completed_at: now } : {}),
      })
      .eq('id', assignment.id);
    if (updateError) throw updateError;
    await fetchState();
  };

  // Manual mastery mark (PRD §5.6 "I'll mark it myself, anytime").
  const toggleMastered = async (questionNumber: number) => {
    if (!supabase || !assignment) throw new Error('No active program run');
    const row = state.mastery.find((m) => m.question_number === questionNumber);
    if (!row) return;
    const { error } = await supabase
      .from('question_mastery')
      .update({ state: row.state === 'mastered' ? 'reviewing' : 'mastered' })
      .eq('id', row.id);
    if (error) throw error;
    await fetchState();
  };

  // Restarting keeps history intact (PRD §5.7): position returns to Q1,
  // mastery rows and completed_at history are not deleted.
  const restartProgram = async () => {
    if (!supabase || !assignment) throw new Error('No active program run');
    const { error } = await supabase
      .from('catechism_assignments')
      .update({ current_question: 1, completed_at: null })
      .eq('id', assignment.id);
    if (error) throw error;
    await fetchState();
  };

  return {
    ...state,
    assignment,
    loading,
    startProgram,
    savePacing,
    completeSession,
    toggleMastered,
    restartProgram,
    refetch: fetchState,
  };
};
