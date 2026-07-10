'use client';

// Today's session (mockups 4a→4d, PRD §5.2): one held thought per screen,
// centered whitespace, a quiet dot-and-arrow progression — new material, then
// review, then scripture & prayer, then done. Never a quiz app; deeper
// material lives one tap away, never inline.
import Link from 'next/link';
import { useEffect, useMemo, useRef, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { getActiveChildId } from '@/lib/activeChild';
import {
  buildSessionPlan,
  getProgram,
  nextSessionDayName,
  type ReviewMark,
} from '@/lib/programs';
import { getPrayer, getWscQuestion } from '@/lib/programContent';

type Step =
  | { type: 'new'; questionNumber: number }
  | { type: 'review' }
  | { type: 'scripture' }
  | { type: 'done' };

function Dots({ count, active }: { count: number; active: number }) {
  return (
    <div className="flex gap-[7px]">
      {Array.from({ length: count }, (_, i) => (
        <span
          key={i}
          className={`h-[5px] w-[5px] rounded-full ${i === active ? 'bg-ink' : 'bg-hairline'}`}
        />
      ))}
    </div>
  );
}

function Frame({
  children,
  footer,
  top,
}: {
  children: React.ReactNode;
  footer: React.ReactNode;
  top: React.ReactNode;
}) {
  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex items-center justify-between px-6 pt-5">{top}</div>
      <div className="flex flex-1 flex-col items-center justify-center px-10 py-10 text-center">
        {children}
      </div>
      <div className="pb-11 text-center">{footer}</div>
    </div>
  );
}

export function SessionClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
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
    assignment, mastery, pacing, loading: stateLoading, completeSession,
  } = useProgramState(program, child);

  // The plan is frozen at session start so mid-session state writes can't
  // reshuffle the steps.
  const plan = useMemo(() => {
    if (!assignment) return null;
    return buildSessionPlan(
      assignment.current_question,
      program.totalQuestions,
      mastery,
      pacing,
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [assignment?.id, stateLoading]);

  const steps: Step[] = useMemo(() => {
    if (!plan || plan.isComplete) return [];
    const list: Step[] = plan.newQuestions.map((questionNumber) => ({
      type: 'new' as const,
      questionNumber,
    }));
    if (plan.reviewQuestions.length) list.push({ type: 'review' });
    list.push({ type: 'scripture' });
    list.push({ type: 'done' });
    return list;
  }, [plan]);

  const [stepIndex, setStepIndex] = useState(0);
  const [marks, setMarks] = useState<Record<number, boolean>>({});
  const [scripture, setScripture] = useState<{ citation: string; text: string | null } | null>(null);
  const persisted = useRef(false);

  const sessionNumber = mastery.length > 0
    ? Math.max(...mastery.map((m) => m.exposures)) + 1
    : 1;

  // Scripture for the session: the first new question's first proof text.
  const firstNew = plan?.newQuestions[0] ?? null;
  const firstNewQuestion = firstNew !== null ? getWscQuestion(firstNew) : null;
  useEffect(() => {
    const osis = firstNewQuestion?.proofTexts[0];
    if (!osis) return;
    fetch(`/api/esv?osis=${encodeURIComponent(osis)}`)
      .then((r) => r.json())
      .then((data: { citation: string; text: string | null }) => setScripture(data))
      .catch(() => setScripture(null));
  }, [firstNewQuestion?.proofTexts]);

  // Persist exactly once when the done step is reached.
  const step = steps[stepIndex];
  useEffect(() => {
    if (step?.type !== 'done' || persisted.current || !plan) return;
    persisted.current = true;
    const reviewMarks: ReviewMark[] = plan.reviewQuestions.map((q) => ({
      questionNumber: q,
      recited: marks[q] ?? false,
    }));
    completeSession(plan, reviewMarks).catch(() => {
      persisted.current = false;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step?.type]);

  if (authLoading || childrenLoading || stateLoading) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  if (!user || !child || !assignment || !plan) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">No Session Yet</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          <Link href={`/programs/${slug}`} className="dotted-link text-ink">
            Start the program
          </Link>
          {' '}for a child first — the session builds itself from their plan.
        </p>
      </div>
    );
  }

  if (plan.isComplete) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">The Plan Is Complete</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          <Link href={`/programs/${slug}`} className="dotted-link text-ink">
            Back to the program
          </Link>
          {' '}to restart it, or start another.
        </p>
      </div>
    );
  }

  const backTarget = stepIndex === 0 ? `/programs/${slug}` : null;
  const top = (
    <>
      {step.type !== 'done' ? (
        backTarget ? (
          <Link href={backTarget} aria-label="Back to program" className="font-display text-[15px] text-ink no-underline">←</Link>
        ) : (
          <button
            type="button"
            aria-label="Back"
            onClick={() => setStepIndex((i) => Math.max(0, i - 1))}
            className="cursor-pointer border-none bg-transparent p-0 font-display text-[15px] text-ink"
          >
            ←
          </button>
        )
      ) : <span className="w-[15px]" />}
      <Dots count={steps.length} active={stepIndex} />
      <span className="w-[15px]" aria-hidden="true" />
    </>
  );

  if (step.type === 'new') {
    const q = getWscQuestion(step.questionNumber);
    return (
      <Frame
        top={top}
        footer={(
          <button
            type="button"
            onClick={() => setStepIndex((i) => i + 1)}
            className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.12em] text-ink"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            {steps[stepIndex + 1]?.type === 'review' ? 'Next: Review →' : 'Next: Scripture & Prayer →'}
          </button>
        )}
      >
        <div className="label-caps mb-1.5 text-[10px] tracking-[0.14em] text-ink-3">
          {child.name} · Session {sessionNumber}
        </div>
        <div className="label-caps mb-6 text-[10px] tracking-[0.14em] text-ochre">
          New · Question {step.questionNumber}
        </div>
        <blockquote className="m-0 font-body text-[19px] italic leading-[1.6] text-ink">
          Q. {q?.question}
          <br />
          <br />
          A. {q?.answer}
        </blockquote>
      </Frame>
    );
  }

  if (step.type === 'review') {
    const allMarked = plan.reviewQuestions.every((q) => q in marks);
    return (
      <Frame
        top={top}
        footer={(
          <button
            type="button"
            disabled={!allMarked}
            onClick={() => setStepIndex((i) => i + 1)}
            className={`label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.12em] ${allMarked ? 'text-ink' : 'text-muted'}`}
            style={{ borderBottom: `1px dotted ${allMarked ? 'var(--color-ink)' : 'var(--color-muted)'}` }}
          >
            Next: Scripture & Prayer →
          </button>
        )}
      >
        <div className="label-caps mb-10 text-[10px] tracking-[0.14em] text-ink-3">Review</div>
        <div className="flex w-full flex-col gap-10">
          {plan.reviewQuestions.map((n) => {
            const q = getWscQuestion(n);
            const marked = n in marks;
            return (
              <div key={n} className="w-full">
                <div className="mb-3 font-body text-base italic text-ink">
                  Q. {n} — {q?.question?.replace(/\?$/, '').toLowerCase()}
                </div>
                {marked ? (
                  <div className="label-caps text-[9.5px] tracking-[0.1em] text-ochre">
                    {marks[n] ? '✓ Recited' : 'Needs Practice'}
                  </div>
                ) : (
                  <div className="label-caps flex justify-center gap-5 text-[9.5px] tracking-[0.1em]">
                    <button
                      type="button"
                      onClick={() => setMarks((m) => ({ ...m, [n]: true }))}
                      aria-label={`Mark Q. ${n} recited without help`}
                      className="cursor-pointer border-none bg-transparent pb-0.5 font-display text-[9.5px] tracking-[0.1em] uppercase text-ink"
                      style={{ borderBottom: '1px dotted var(--color-ink)' }}
                    >
                      Recited
                    </button>
                    <button
                      type="button"
                      onClick={() => setMarks((m) => ({ ...m, [n]: false }))}
                      aria-label={`Mark Q. ${n} as needing practice`}
                      className="cursor-pointer border-none bg-transparent pb-0.5 font-display text-[9.5px] tracking-[0.1em] uppercase text-ink-3"
                      style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
                    >
                      Needs Practice
                    </button>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </Frame>
    );
  }

  if (step.type === 'scripture') {
    const prayer = firstNew !== null ? getPrayer(firstNew, child.name) : null;
    return (
      <Frame
        top={top}
        footer={(
          <button
            type="button"
            onClick={() => setStepIndex((i) => i + 1)}
            className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.12em] text-ink"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            Finish Session →
          </button>
        )}
      >
        {scripture && (
          <>
            <div className="label-caps mb-5 text-[10px] tracking-[0.14em] text-ink-3">Scripture</div>
            <blockquote className="m-0 mb-12 font-body text-[17px] italic leading-[1.6] text-ink">
              {scripture.text ?? 'Read together:'}
              <cite className="label-caps mt-2.5 block text-[10px] not-italic tracking-[0.12em] text-ink-3">
                {scripture.citation}
              </cite>
            </blockquote>
          </>
        )}
        <div className="label-caps mb-4 text-[10px] tracking-[0.14em] text-ink-3">A Prayer to Close</div>
        {prayer ? (
          <p className="m-0 font-body text-[14.5px] italic leading-[1.7] text-ink">{prayer}</p>
        ) : (
          <p className="m-0 text-[13px] italic text-heart-reviewing">
            The prayer for this question isn’t written yet — close in your own words.
          </p>
        )}
      </Frame>
    );
  }

  // done
  const recitedList = plan.reviewQuestions.filter((q) => marks[q]);
  const summaryParts: string[] = [];
  if (recitedList.length) {
    summaryParts.push(
      `${child.name} recited ${recitedList.map((q) => `Q. ${q}`).join(' and ')} without help`,
    );
  }
  if (plan.newQuestions.length) {
    summaryParts.push(
      `heard ${plan.newQuestions.map((q) => `Q. ${q}`).join(' and ')} for the first time`,
    );
  }
  const summary = summaryParts.length
    ? `${summaryParts.join(', and ')}.`
    : `${child.name} sat with today’s questions.`;

  return (
    <Frame
      top={<div className="mx-auto"><Dots count={steps.length} active={stepIndex} /></div>}
      footer={(
        <>
          <div className="label-caps mb-4 text-[9.5px] tracking-[0.1em] text-ink-3">
            Next Session · {nextSessionDayName(pacing.sessionsPerWeek)}
          </div>
          <Link
            href={`/programs/${slug}`}
            className="label-caps dotted-link text-[11px] tracking-[0.12em] text-ink"
          >
            Back to Program
          </Link>
        </>
      )}
    >
      <div className="mb-5 text-[22px] text-ochre" aria-hidden="true">♥</div>
      <h1 className="mb-3 font-display text-[19px] font-semibold">Session Complete</h1>
      <p className="m-0 text-sm italic leading-[1.7] text-ink-2">{summary}</p>
    </Frame>
  );
}
