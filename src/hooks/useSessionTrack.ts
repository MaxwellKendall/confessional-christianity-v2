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

  // Arriving with a valid ?start=N positions the session there: a fresh
  // visitor starts a track at N, while someone with a track jumps to N
  // (browsing — milestones untouched). This is how the landing's Contents
  // links open a specific question. Without the param, an existing track
  // resumes where it left off and a fresh visitor begins at Q1.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const requestedStart = Number(params.get('start'));
    const validStart = Number.isInteger(requestedStart)
      && requestedStart >= 1
      && requestedStart <= program.totalQuestions
      ? requestedStart
      : null;
    const existing = getLocalCatechismTrack(program.contentId);
    if (validStart !== null) {
      setLocalTrack(
        existing
          ? jumpToLocalQuestion(program.contentId, validStart, program.totalQuestions)
          : startLocalCatechismTrack(program.contentId, validStart),
      );
    } else {
      setLocalTrack(existing ?? startLocalCatechismTrack(program.contentId, 1));
    }
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
