'use client';

// One session model, signed in or out (mockup 8a, turn 9): this hook is what
// makes that true in code, not just in the UI. It wraps whichever backing
// store applies — Supabase for a signed-in child, localStorage for a guest —
// behind a single shape so SessionClient, JumpToQuestionClient, and
// MilestonesClient don't each re-implement the branch.
import { useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { getActiveChildId } from '@/lib/activeChild';
import {
  advanceLocalQuestion,
  getLocalCatechismTrack,
  getLocalLearner,
  DEFAULT_LEARNER_NAME,
  jumpToLocalQuestion,
  startLocalCatechismTrack,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import type { ProgramDefinition } from '@/lib/programs';

export interface SessionTrack {
  loading: boolean;
  isSignedIn: boolean;
  /** signed in, no assignment yet — send them to /start */
  needsStart: boolean;
  questionNumber: number | null;
  isComplete: boolean;
  totalQuestions: number;
  /** null for a guest with no name set yet */
  childName: string | null;
  childAge: number | null;
  advance: () => void;
  jumpTo: (n: number) => void;
}

export const useSessionTrack = (program: ProgramDefinition): SessionTrack => {
  const { user, loading: authLoading } = useAuth();
  const { children, loading: childrenLoading } = useChildren();
  const [activeId, setActiveId] = useState<string | null>(null);

  useEffect(() => {
    if (!children.length) return;
    const stored = getActiveChildId();
    setActiveId(children.some((c) => c.id === stored) ? stored : children[0].id);
  }, [children]);

  const child = children.find((c) => c.id === activeId) ?? null;
  const {
    assignment, loading: stateLoading, advanceProgram, jumpToProgram,
  } = useProgramState(program, child);

  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);
  const [localName, setLocalName] = useState<string | null>(null);
  const [localAge, setLocalAge] = useState<number | null>(null);

  // Guests get zero extra steps: no track yet means starting at Q1 (or a
  // valid ?start=N) the moment they arrive.
  useEffect(() => {
    if (authLoading || user) return;
    const params = new URLSearchParams(window.location.search);
    const requestedStart = Number(params.get('start'));
    const validStart = Number.isInteger(requestedStart)
      && requestedStart >= 1
      && requestedStart <= program.totalQuestions
      ? requestedStart
      : 1;
    setLocalTrack(
      getLocalCatechismTrack(program.contentId)
        ?? startLocalCatechismTrack(program.contentId, validStart),
    );
    const learner = getLocalLearner();
    setLocalName(learner.name === DEFAULT_LEARNER_NAME ? null : learner.name);
    setLocalAge(learner.age);
  }, [authLoading, user, program.contentId, program.totalQuestions]);

  if (authLoading) {
    return {
      loading: true,
      isSignedIn: false,
      needsStart: false,
      questionNumber: null,
      isComplete: false,
      totalQuestions: program.totalQuestions,
      childName: null,
      childAge: null,
      advance: () => {},
      jumpTo: () => {},
    };
  }

  if (!user) {
    const questionNumber = localTrack
      ? Math.min(localTrack.currentQuestion, program.totalQuestions)
      : null;
    return {
      loading: !localTrack,
      isSignedIn: false,
      needsStart: false,
      questionNumber,
      isComplete: Boolean(localTrack) && localTrack!.currentQuestion > program.totalQuestions,
      totalQuestions: program.totalQuestions,
      childName: localName,
      childAge: localAge,
      advance: () => setLocalTrack(advanceLocalQuestion(program.contentId, program.totalQuestions)),
      jumpTo: (n: number) => setLocalTrack(
        jumpToLocalQuestion(program.contentId, n, program.totalQuestions),
      ),
    };
  }

  const loading = childrenLoading || stateLoading;
  const questionNumber = assignment
    ? Math.min(assignment.current_question, program.totalQuestions)
    : null;

  return {
    loading,
    isSignedIn: true,
    needsStart: !loading && !assignment,
    questionNumber,
    isComplete: Boolean(assignment) && assignment!.current_question > program.totalQuestions,
    totalQuestions: program.totalQuestions,
    childName: child?.name ?? null,
    childAge: child?.age ?? null,
    advance: () => { advanceProgram(); },
    jumpTo: (n: number) => { jumpToProgram(n); },
  };
};
