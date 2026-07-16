'use client';

// Today's session (mockup 8a): the question, its Scripture cited per-clause,
// and Pray/Resources entry points (QuestionCard), plus Next Question.
// Arriving with ?worship= means Family Worship's Professing Faith step (11f)
// handed off here; the screen is identical — only "Next" returns to the
// service at the following step instead of staying.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { useSessionTrack } from '@/hooks/useSessionTrack';
import { getProgram } from '@/lib/programs';
import type { Daypart } from '@/lib/worship';
import { QuestionCard } from './QuestionCard';

export function SessionClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const track = useSessionTrack(program);
  const router = useRouter();

  const [worshipReturn, setWorshipReturn] = useState<Daypart | null>(null);
  useEffect(() => {
    const daypart = new URLSearchParams(window.location.search).get('worship');
    if (daypart === 'morning' || daypart === 'evening') setWorshipReturn(daypart);
  }, []);

  if (track.loading) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  if (track.isComplete) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 heading-page">Catechism Complete</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          Every question has been seen.{' '}
          <Link href={`/programs/${slug}`} className="dotted-link text-ink">
            Back to the catechism
          </Link>
          {' '}to begin again, or browse another catechism.
        </p>
      </div>
    );
  }

  const questionNumber = track.questionNumber!;

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="px-6 pt-5 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">
          {program.title}
        </div>
        <Link
          href={`/programs/${slug}/session/jump`}
          className="label-caps mt-1 inline-block text-[9.5px] tracking-[0.12em] text-ochre no-underline"
          style={{ borderBottom: '1px dotted var(--color-ochre)' }}
        >
          Question {questionNumber} of {program.totalQuestions} ▾
        </Link>
      </div>

      <div className="flex flex-1 flex-col items-center justify-center px-[34px] py-6 text-center">
        <QuestionCard program={program} questionNumber={questionNumber} childName="your child" />
      </div>

      <div className="border-t border-hairline px-6 pb-10">
        <div className="flex items-center justify-between pt-4">
          {questionNumber > 1 ? (
            <button
              type="button"
              onClick={() => track.jumpTo(questionNumber - 1)}
              aria-label="Previous question"
              className="label-caps cursor-pointer border-none bg-transparent p-0 text-[11px] tracking-[0.1em] text-ink-3"
            >
              ← Prev
            </button>
          ) : (
            <span />
          )}
          <button
            type="button"
            onClick={() => {
              track.advance();
              if (worshipReturn) router.push(`/worship/${worshipReturn}?step=6`);
            }}
            className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.1em] text-ink"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            {worshipReturn ? 'Continue Worship →' : 'Next →'}
          </button>
        </div>
        <div className="text-center mt-3">
          <Link
            href={`/programs/${slug}/session/milestones`}
            className="font-body text-[11.5px] italic text-ink-3 no-underline"
            style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
          >
            See Milestones →
          </Link>
        </div>
      </div>
    </div>
  );
}
