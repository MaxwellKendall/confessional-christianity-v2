'use client';

// Service complete (mockup 11j): the worship streak increments alongside —
// not instead of — the question milestones, and the screen says so in one
// line. Arriving here records the completion; recording is idempotent, so a
// reload doesn't double-count.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { getActiveLocalCatechismTrack } from '@/lib/localCatechismProgress';
import { getWorshipStreak, recordWorshipCompletion } from '@/lib/localWorship';
import { PROGRAMS, type ProgramDefinition } from '@/lib/programs';
import type { Daypart } from '@/lib/worship';

interface Completion {
  streak: number;
  program: ProgramDefinition;
  answeredQuestion: number | null;
}

export function WorshipCompleteClient({ daypart }: { daypart: Daypart }) {
  const [completion, setCompletion] = useState<Completion | null>(null);

  useEffect(() => {
    recordWorshipCompletion(daypart);
    const track = getActiveLocalCatechismTrack();
    const program = (track && PROGRAMS.find((p) => p.contentId === track.catechismId))
      ?? PROGRAMS[0];
    // The question professed in step 5 is the one just advanced past.
    const answered = track ? track.currentQuestion - 1 : 0;
    setCompletion({
      streak: getWorshipStreak(),
      program,
      answeredQuestion: answered >= 1 ? Math.min(answered, program.totalQuestions) : null,
    });
  }, [daypart]);

  if (!completion) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const { streak, program, answeredQuestion } = completion;
  const summary = [
    `${streak}-day worship streak`,
    answeredQuestion ? `Question ${answeredQuestion} of ${program.totalQuestions} answered` : null,
  ].filter(Boolean).join(' · ');

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex flex-1 flex-col items-center justify-center px-9 py-6 text-center">
        <div
          className="mb-5 flex h-11 w-11 items-center justify-center rounded-full border-[1.5px] border-ochre"
          aria-hidden="true"
        >
          <svg width="18" height="14" viewBox="0 0 18 14">
            <path d="M1 7l6 6 10-12" fill="none" stroke="var(--color-ochre)" strokeWidth="1.6" />
          </svg>
        </div>
        <h1 className="mb-2 heading-page">
          {daypart === 'morning' ? 'Morning' : 'Evening'} Worship Complete
        </h1>
        <p className="m-0 mb-6 font-body text-[13px] italic leading-relaxed text-ink-3">{summary}</p>
        <div className="mb-6 h-px w-9 bg-hairline" aria-hidden="true" />
        <p className="m-0 font-body text-[13px] italic text-ink-2">
          {daypart === 'morning' ? 'See you again this evening.' : 'See you in the morning.'}
        </p>
      </div>

      <div className="flex flex-col items-center gap-3 border-t border-hairline px-6 pt-3.5 pb-9">
        <Link
          href="/worship"
          className="label-caps pb-0.5 text-[11px] tracking-[0.08em] text-ink no-underline"
          style={{ borderBottom: '1px dotted var(--color-ink)' }}
        >
          Back Home
        </Link>
        <Link
          href={`/programs/${program.slug}/session/milestones`}
          className="font-body text-[12px] italic text-ink-3 no-underline"
          style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
        >
          See Milestones →
        </Link>
      </div>
    </div>
  );
}
