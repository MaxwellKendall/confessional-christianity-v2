'use client';

// Begin Family Worship (mockup 11a): the AM/PM entry point, an order-of-
// service preview resolved for today, and the worship streak beside — not
// instead of — the question milestones. The hurried path stays one tap away:
// "Just answer today's question" goes straight to the session (8a).
import Link from 'next/link';
import { useEffect, useState } from 'react';

import {
  getActiveLocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { getWorshipStreak } from '@/lib/localWorship';
import { PROGRAMS, type ProgramDefinition } from '@/lib/programs';
import { getService, stepDetail, type Daypart } from '@/lib/worship';

interface Landing {
  daypart: Daypart;
  program: ProgramDefinition;
  questionNumber: number;
  streak: number;
}

export function WorshipLandingClient() {
  const [landing, setLanding] = useState<Landing | null>(null);

  // Everything here is device-local (the track, the streak) or time-of-day
  // (the daypart default), so it resolves after mount, like HomeClient.
  // Reading the track never starts one — browsing the worship landing must
  // not mutate catechism state.
  useEffect(() => {
    const track = getActiveLocalCatechismTrack();
    const program = (track && PROGRAMS.find((p) => p.contentId === track.catechismId))
      ?? PROGRAMS[0];
    setLanding({
      daypart: new Date().getHours() >= 16 ? 'evening' : 'morning',
      program,
      questionNumber: track ? Math.min(track.currentQuestion, program.totalQuestions) : 1,
      streak: getWorshipStreak(),
    });
  }, []);

  if (!landing) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const { daypart, program, questionNumber, streak } = landing;
  const service = getService(daypart, new Date());
  const setDaypart = (next: Daypart) => setLanding({ ...landing, daypart: next });

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="px-6 pt-6 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">For Your Household</div>
        <h1 className="mt-1.5 mb-1 heading-page">Family Worship</h1>
        <p className="m-0 font-body text-[12.5px] italic text-ink-3">About 15 minutes, together</p>
      </div>

      <div className="flex justify-center gap-2 pt-5" role="group" aria-label="Morning or evening">
        {(['morning', 'evening'] as const).map((part) => (
          <button
            key={part}
            type="button"
            onClick={() => setDaypart(part)}
            aria-pressed={daypart === part}
            className={`label-caps cursor-pointer rounded-full px-5.5 py-1.75 text-[10px] tracking-[0.1em] capitalize ${
              daypart === part
                ? 'border border-ink bg-ink text-card'
                : 'border border-hairline bg-transparent text-ink-3'
            }`}
          >
            {part}
          </button>
        ))}
      </div>

      <div className="flex-1 px-6 pt-5.5 pb-2.5">
        <div className="label-caps mb-3.5 text-center text-[9px] tracking-[0.14em] text-ink-3">
          This {daypart === 'morning' ? 'Morning' : 'Evening'}&rsquo;s Order
        </div>
        <ol className="m-0 list-none p-0">
          {service.steps.map((step, i) => {
            const detail = step.elements[0]?.type === 'catechism'
              ? `Q${questionNumber} of ${program.totalQuestions}`
              : stepDetail(step);
            return (
              <li
                key={step.role}
                className={`flex items-center gap-3 py-2.5 ${i < service.steps.length - 1 ? 'border-b border-fill' : ''}`}
              >
                <span className="w-5 shrink-0 font-display text-[10px] text-ochre">{i + 1}</span>
                <span className="font-body text-[13.5px] text-ink">
                  {step.role}
                  {detail ? ` — ${detail}` : ''}
                </span>
              </li>
            );
          })}
        </ol>

        {streak > 0 && (
          <div className="mt-5 flex items-center justify-center gap-2">
            <span className="h-[7px] w-[7px] rounded-full bg-ochre" aria-hidden="true" />
            <span className="label-caps text-[10px] tracking-[0.08em] text-ink-3">
              {streak}-day worship streak
            </span>
          </div>
        )}
      </div>

      <div className="border-t border-hairline px-6 pt-3.5 pb-9">
        <Link href={`/worship/${daypart}`} className="action-button">
          Begin Family Worship
        </Link>
        <div className="mt-3.5 text-center">
          <Link
            href={`/programs/${program.slug}/session`}
            className="font-body text-[12px] italic text-ink-3 no-underline"
            style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
          >
            Just answer today&rsquo;s question →
          </Link>
        </div>
      </div>
    </div>
  );
}
