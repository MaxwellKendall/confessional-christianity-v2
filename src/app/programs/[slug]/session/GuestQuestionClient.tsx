'use client';

// The signed-out "aha" screen (mockup 8a, supersedes 7c): one question, its
// Scripture cited per-clause, Pray/Reflections entry points, a quiet save
// affordance, and Next Question — all on one screen, reached with zero
// account. Next Question advances in place; the save gate (7d) is only ever
// entered by tapping save, and declining it never loses the place here.
// This is the same question card the signed-in session renders for its "new
// question" step (QuestionCard) — the only difference is what surrounds it.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import {
  advanceLocalQuestion,
  getLocalCatechismTrack,
  getLocalLearner,
  DEFAULT_LEARNER_NAME,
  startLocalCatechismTrack,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { getProgram } from '@/lib/programs';
import { QuestionCard } from './QuestionCard';

export function GuestQuestionClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const [track, setTrack] = useState<LocalCatechismTrack | null>(null);
  const [learnerName, setLearnerName] = useState<string | null>(null);

  // Zero extra steps: a visitor with no track starts at Q1 (or a valid
  // ?start=N) the moment they arrive.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const requestedStart = Number(params.get('start'));
    const validStart = Number.isInteger(requestedStart)
      && requestedStart >= 1
      && requestedStart <= program.totalQuestions
      ? requestedStart
      : 1;
    setTrack(
      getLocalCatechismTrack(program.catechismId)
        ?? startLocalCatechismTrack(program.catechismId, validStart),
    );
    const learner = getLocalLearner();
    setLearnerName(learner.name === DEFAULT_LEARNER_NAME ? null : learner.name);
  }, [program.catechismId, program.totalQuestions]);

  const questionNumber = track ? Math.min(track.currentQuestion, program.totalQuestions) : null;

  if (!track) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  if (track.currentQuestion > program.totalQuestions) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Catechism Complete</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          {learnerName ?? 'Your child'} has seen every question.{' '}
          <Link href={`/programs/${slug}/save`} className="dotted-link text-ink">
            Save this progress
          </Link>
          {' '}to keep it on every device.
        </p>
      </div>
    );
  }

  const possessive = learnerName ? `${learnerName}’s` : 'Your';

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="px-6 pt-5 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">
          {possessive} {program.title}
        </div>
        <div className="label-caps mt-1 text-[9.5px] tracking-[0.12em] text-ochre">
          Question {questionNumber} of {program.totalQuestions}
        </div>
      </div>

      <div className="flex flex-1 flex-col items-center justify-center px-[34px] py-6 text-center">
        {questionNumber !== null && (
          <QuestionCard slug={slug} questionNumber={questionNumber} childName={learnerName ?? 'your child'} />
        )}
      </div>

      <div className="border-t border-hairline px-6 pb-10">
        <div className="flex items-center justify-between pt-4">
          <Link
            href={`/programs/${slug}/save`}
            aria-label={`Save ${learnerName ?? 'your child'}’s progress`}
            className="label-caps flex items-center gap-1.5 text-[10px] tracking-[0.08em] text-ink-3 no-underline"
          >
            <svg width="12" height="14" viewBox="0 0 12 14" aria-hidden="true">
              <path d="M1 1h10v12l-5-3.5L1 13z" fill="none" stroke="currentColor" strokeWidth="1.2" />
            </svg>
            Save {possessive} Progress
          </Link>
          <button
            type="button"
            onClick={() => setTrack(advanceLocalQuestion(program.catechismId, program.totalQuestions))}
            className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.1em] text-ink"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            Next Question →
          </button>
        </div>
      </div>
    </div>
  );
}
