'use client';

// Data access for one child's run of a program: the catechism assignment
// and per-question mastery. There's no pacing/scheduling anymore (turn 9) —
// a session just advances the assignment's position one question at a time.
import { useCallback, useEffect, useState } from 'react';

import { getSupabaseBrowserClient } from '@/lib/supabase/client';
import type { ProgramDefinition } from '@/lib/programs';
import type {
  CatechismAssignmentRow,
  ChildWithRole,
  QuestionMasteryRow,
} from '@/lib/database.types';

export interface ProgramRunState {
  assignment: CatechismAssignmentRow | null;
  mastery: QuestionMasteryRow[];
}

export const useProgramState = (program: ProgramDefinition, child: ChildWithRole | null) => {
  const supabase = getSupabaseBrowserClient();
  const [state, setState] = useState<ProgramRunState>({
    assignment: null,
    mastery: [],
  });
  const [loading, setLoading] = useState(true);

  const assignment = child?.catechism_assignments
    ?.find((a) => a.catechism_id === program.contentId) ?? null;

  const fetchState = useCallback(async () => {
    if (!supabase || !child || !assignment) {
      setState({
        assignment: assignment ?? null,
        mastery: [],
      });
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const masteryRes = await supabase
        .from('question_mastery')
        .select('*')
        .eq('assignment_id', assignment.id);
      setState({
        assignment,
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

  // Starting a program is choosing a child for it (PRD §5.5): just the
  // assignment now — no pacing row to seed.
  const startProgram = async (targetChild: ChildWithRole, startingQuestion = 1) => {
    if (!supabase) throw new Error('Supabase not configured');
    const { data, error } = await supabase
      .from('catechism_assignments')
      .insert({
        child_id: targetChild.id,
        catechism_id: program.contentId,
        current_question: startingQuestion,
      })
      .select()
      .single();
    if (error) throw error;
    return data as CatechismAssignmentRow;
  };

  // "Next Question" (mockup 8a): marks the question being left as seen and
  // advances the position by one, capped one past the end so a finished
  // track reads as complete — the signed-in twin of advanceLocalQuestion.
  const advanceProgram = async () => {
    if (!supabase || !assignment) throw new Error('No active program run');
    const now = new Date().toISOString();
    const q = assignment.current_question;
    if (q <= program.totalQuestions && !state.mastery.some((m) => m.question_number === q)) {
      const { error } = await supabase.from('question_mastery').upsert(
        {
          assignment_id: assignment.id,
          question_number: q,
          state: 'reviewing',
          recited_streak: 0,
          exposures: 1,
          last_reviewed_at: now,
        },
        { onConflict: 'assignment_id,question_number' },
      );
      if (error) throw error;
    }
    const nextQuestion = Math.min(program.totalQuestions + 1, q + 1);
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

  // Jumping to an arbitrary question (mockup 8d) repositions the assignment
  // without touching mastery — it's browsing, not re-introducing material,
  // matching jumpToLocalQuestion's rule for guests.
  const jumpToProgram = async (questionNumber: number) => {
    if (!supabase || !assignment) throw new Error('No active program run');
    const clamped = Math.min(program.totalQuestions, Math.max(1, questionNumber));
    const { error } = await supabase
      .from('catechism_assignments')
      .update({ current_question: clamped })
      .eq('id', assignment.id);
    if (error) throw error;
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
    advanceProgram,
    jumpToProgram,
    toggleMastered,
    restartProgram,
    refetch: fetchState,
  };
};
