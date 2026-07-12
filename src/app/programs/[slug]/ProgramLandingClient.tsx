'use client';

// Program landing (mockup 5d) and its completion state (5e, PRD §5.7).
// The child the plan belongs to is shown plainly — "Eli's Plan" — per §5.5.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { Heart } from '@/components/Heart';
import { ProgressBar } from '@/components/ProgressBar';
import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { getActiveChildId } from '@/lib/activeChild';
import {
  getLocalCatechismTrack,
  localProgressLabel,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { getProgram, masteryStateFor } from '@/lib/programs';
import { getWscQuestion, hasPrayer } from '@/lib/programContent';

const CONTENTS_WINDOW = 6;

export function ProgramLandingClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const { user, loading: authLoading } = useAuth();
  const { children, loading: childrenLoading } = useChildren();
  const [activeId, setActiveId] = useState<string | null>(null);
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);

  useEffect(() => {
    if (!children.length) return;
    const stored = getActiveChildId();
    setActiveId(children.some((c) => c.id === stored) ? stored : children[0].id);
  }, [children]);

  useEffect(() => {
    if (authLoading || user) return;
    setLocalTrack(getLocalCatechismTrack(program.catechismId));
  }, [authLoading, program.catechismId, user]);

  const child = children.find((c) => c.id === activeId) ?? null;
  const {
    assignment, mastery, pacing, toggleMastered, restartProgram,
  } = useProgramState(program, child);

  const header = (
    <>
      <div className="px-5 pt-5 label-caps text-[9.5px] tracking-[0.1em]">
        <Link href="/programs" className="dotted-link text-ink-3">Catechisms</Link>
      </div>
      <div className="px-8 pt-4 text-center">
        <div className="label-caps mb-3 text-[9.5px] text-ink-3">Westminster Standards</div>
        <h1 className="mb-2 font-display text-[21px] font-semibold leading-[1.3]">
          {program.title}
        </h1>
        <p className="mb-3 text-[13.5px] italic leading-relaxed text-ink-2">
          Each question paired with proof-text Scripture, a closing prayer,
          and progress milestones you can save on this device.
        </p>
        {child && (
          <div className="label-caps text-[10px] tracking-[0.1em] text-ink-3">
            {[
              child.age !== null ? `Configured for age ${child.age}` : null,
              `~${program.estimatedMinutes} minutes`,
              `${pacing.sessionsPerWeek} sessions a week`,
            ].filter(Boolean).join(' · ')}
          </div>
        )}
      </div>
    </>
  );

  const loading = authLoading || childrenLoading;
  if (loading) return <div>{header}</div>;

  // Completed (5e): a real, acknowledged state with two paths forward.
  if (child && assignment && assignment.current_question > program.totalQuestions) {
    return (
      <div className="flex flex-1 flex-col">
        <div className="px-6 pt-4">
          <Link href="/" aria-label="Back to homepage" className="font-display text-[15px] text-ink no-underline">←</Link>
        </div>
        <div className="flex flex-1 flex-col items-center justify-center px-10 py-16 text-center">
          <div className="mb-5 text-2xl text-ochre" aria-hidden="true">♥</div>
          <div className="label-caps mb-3 text-[9.5px] text-ink-3">
            {child.name}’s Shorter Catechism · Complete
          </div>
          <h1 className="mb-3.5 font-display text-xl font-semibold leading-[1.4]">
            All {program.totalQuestions} Questions of the Shorter Catechism
          </h1>
          <p className="text-[13.5px] italic leading-[1.7] text-ink-2">
            {child.name} has recited every question, start to finish. Nothing
            here is lost — the history stays exactly as it is.
          </p>
        </div>
        <div className="flex flex-col items-center gap-4 px-6 pb-11">
          <button
            type="button"
            onClick={() => restartProgram()}
            className="action-button w-full cursor-pointer bg-transparent"
          >
            Restart From Question 1
          </button>
          <Link href="/programs" className="dotted-link text-[13px] italic text-ink-2">
            Start Another Catechism for {child.name}
          </Link>
        </div>
      </div>
    );
  }

  const visibleCurrentQuestion = assignment?.current_question ?? localTrack?.currentQuestion ?? 1;
  const contentsStart = assignment || localTrack
    ? Math.max(1, Math.min(visibleCurrentQuestion - 3, program.totalQuestions - CONTENTS_WINDOW + 1))
    : 1;
  const contentsNumbers = Array.from({ length: CONTENTS_WINDOW }, (_, i) => contentsStart + i)
    .filter((n) => n <= program.totalQuestions);

  return (
    <div className="pb-7">
      {header}

      {child && assignment ? (
        <div className="mx-5 mt-6 border-t border-hairline pt-4 text-center">
          <div className="mb-3 font-display text-[17px] font-semibold">{child.name}’s Shorter Catechism</div>
          <div className="mb-2.5 flex items-baseline justify-between">
            <span className="label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
              Question {assignment.current_question} next
            </span>
            <span className="label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
              Q. {Math.min(assignment.current_question - 1, program.totalQuestions)} of {program.totalQuestions}
            </span>
          </div>
          <div className="mb-5">
            <ProgressBar fraction={(assignment.current_question - 1) / program.totalQuestions} />
          </div>
          <Link href={`/programs/${slug}/session`} className="action-button mb-4">
            Continue Today’s Session →
          </Link>
          <div className="text-center">
            <Link href={`/programs/${slug}/pacing`} className="dotted-link text-[12.5px] italic text-ink-2">
              Pacing
            </Link>
          </div>
        </div>
      ) : localTrack ? (
        <div className="mx-5 mt-6 border-t border-hairline pt-4 text-center">
          <div className="mb-3 font-display text-[17px] font-semibold">Continue the Shorter Catechism</div>
          <div className="mb-2.5 flex items-baseline justify-between">
            <span className="label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
              Question {Math.min(localTrack.currentQuestion, program.totalQuestions)} next
            </span>
            <span className="label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
              {localProgressLabel}
            </span>
          </div>
          <div className="mb-5">
            <ProgressBar fraction={(localTrack.currentQuestion - 1) / program.totalQuestions} />
          </div>
          <Link href={`/programs/${slug}/session`} className="action-button mb-4">
            Continue the Shorter Catechism →
          </Link>
          <div className="text-center">
            <Link href={`/programs/${slug}/save`} className="dotted-link text-[12.5px] italic text-ink-2">
              Save this progress to keep it safe
            </Link>
          </div>
        </div>
      ) : (
        <div className="mx-5 mt-6 border-t border-hairline pt-5 text-center">
          {user ? (
            <Link href={`/programs/${slug}/start`} className="action-button">
              Begin the Shorter Catechism
            </Link>
          ) : (
            <>
              <Link href={`/programs/${slug}/start`} className="action-button">
                Begin with a Starting Question
              </Link>
              <p className="mt-3 text-[12.5px] italic text-ink-2">
                No account required. Progress saves on this device.
              </p>
            </>
          )}
        </div>
      )}

      <div className="mx-5 mt-6 border-t border-hairline pt-4">
        <div className="label-caps mb-2 text-[9.5px] text-ink-3">Contents</div>
        <div className="flex flex-col">
          {contentsNumbers.map((n) => {
            const q = getWscQuestion(n);
            const row = mastery.find((m) => m.question_number === n);
            const state = masteryStateFor(row);
            const introduced = Boolean(row) || Boolean(localTrack?.milestones[String(n)]);
            const displayState = row ? state : introduced ? 'reviewing' : 'not_started';
            return (
              <div
                key={n}
                className="flex items-center justify-between gap-3 border-t border-hairline py-2.5 last:border-b"
              >
                <div>
                  <div className={`font-display text-[13px] font-semibold ${introduced || n === visibleCurrentQuestion ? 'text-ink' : 'text-ink-3'}`}>
                    Q. {n} — {q?.question}
                  </div>
                  {!hasPrayer(n) && (
                    <div className="mt-0.5 text-[10.5px] italic text-heart-reviewing">
                      Prayer not yet written
                    </div>
                  )}
                </div>
                {child && assignment && introduced && pacing.masteryRule === 'manual' ? (
                  <button
                    type="button"
                    onClick={() => toggleMastered(n)}
                    aria-label={state === 'mastered' ? `Unmark Q. ${n} mastered` : `Mark Q. ${n} recited without help`}
                    className="cursor-pointer border-none bg-transparent p-0"
                  >
                    <Heart state={state} label="" />
                  </button>
                ) : (
                  <Heart
                    state={displayState}
                    label={`Q. ${n}: ${displayState === 'not_started' ? 'not yet started' : displayState}`}
                  />
                )}
              </div>
            );
          })}
        </div>
        <div className="pt-3.5 pb-1 text-center text-xs italic text-ink-3">
          <span className="text-ochre">♥</span> mastered ·{' '}
          <span className="text-heart-reviewing">♥</span> reviewing ·{' '}
          <span className="text-muted">♡</span> not yet started
        </div>
      </div>
    </div>
  );
}
