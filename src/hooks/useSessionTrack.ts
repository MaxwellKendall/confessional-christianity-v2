'use client';

// The guest session track (mockup 8a): position within a catechism, backed
// entirely by localStorage. SessionClient, JumpToQuestionClient, and
// MilestonesClient all read this one shape instead of touching
// localCatechismProgress directly.
import { useEffect, useState } from 'react';

import {
  advanceLocalQuestion,
  getLocalCatechismTrack,
  jumpToLocalQuestion,
  startLocalCatechismTrack,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import type { ProgramDefinition } from '@/lib/programs';

export interface SessionTrack {
  loading: boolean;
  questionNumber: number | null;
  isComplete: boolean;
  totalQuestions: number;
  advance: () => void;
  jumpTo: (n: number) => void;
}

export const useSessionTrack = (program: ProgramDefinition): SessionTrack => {
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);

  // No track yet means starting at Q1 (or a valid ?start=N) the moment
  // someone arrives — zero extra steps.
  useEffect(() => {
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
  }, [program.contentId, program.totalQuestions]);

  const questionNumber = localTrack
    ? Math.min(localTrack.currentQuestion, program.totalQuestions)
    : null;

  return {
    loading: !localTrack,
    questionNumber,
    isComplete: Boolean(localTrack) && localTrack!.currentQuestion > program.totalQuestions,
    totalQuestions: program.totalQuestions,
    advance: () => setLocalTrack(advanceLocalQuestion(program.contentId, program.totalQuestions)),
    jumpTo: (n: number) => setLocalTrack(
      jumpToLocalQuestion(program.contentId, n, program.totalQuestions),
    ),
  };
};
