'use client';

// Today's session (mockup 8a, turn 9): one screen, signed in or out. The
// question, its Scripture cited per-clause, Pray/Resources entry points
// (QuestionCard), and Next Question are the same either way — the only
// difference is that a guest still has "Save Progress" to do. useSessionTrack
// carries that one distinction; this component never branches on auth itself.
import Link from 'next/link';

import { useSessionTrack } from '@/hooks/useSessionTrack';
import { getProgram } from '@/lib/programs';
import { QuestionCard } from './QuestionCard';

export function SessionClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const track = useSessionTrack(program);

  if (track.loading) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  if (track.needsStart) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Begin the Shorter Catechism</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          Choose who this catechism is for, and where to begin.
        </p>
        <Link href={`/programs/${slug}/start`} className="action-button mt-6">
          Start the Catechism
        </Link>
      </div>
    );
  }

  if (track.isComplete) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Catechism Complete</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          {track.childName ?? 'Your child'} has seen every question.{' '}
          {track.isSignedIn ? (
            <Link href={`/programs/${slug}`} className="dotted-link text-ink">
              Back to the catechism
            </Link>
          ) : (
            <Link href={`/programs/${slug}/save`} className="dotted-link text-ink">
              Save this progress
            </Link>
          )}
          {' '}
          {track.isSignedIn ? 'to begin again, or browse another catechism.' : 'to keep it on every device.'}
        </p>
      </div>
    );
  }

  const possessive = track.childName ? `${track.childName}’s` : 'Your';
  const questionNumber = track.questionNumber!;

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="px-6 pt-5 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">
          {possessive} {program.title}
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
        <QuestionCard program={program} questionNumber={questionNumber} childName={track.childName ?? 'your child'} />
      </div>

      <div className="border-t border-hairline px-6 pb-10">
        <div className="flex items-center justify-between pt-4">
          {track.isSignedIn ? (
            <span />
          ) : (
            <Link
              href={`/programs/${slug}/save`}
              aria-label={`Save ${track.childName ?? 'your child'}’s progress`}
              className="label-caps flex items-center gap-1.5 text-[10px] tracking-[0.08em] text-ink-3 no-underline"
            >
              <svg width="12" height="14" viewBox="0 0 12 14" aria-hidden="true">
                <path d="M1 1h10v12l-5-3.5L1 13z" fill="none" stroke="currentColor" strokeWidth="1.2" />
              </svg>
              Save {possessive} Progress
            </Link>
          )}
          <button
            type="button"
            onClick={() => track.advance()}
            className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.1em] text-ink"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            Next Question →
          </button>
        </div>
        <div className="text-center mt-3">
          <Link
            href={`/programs/${slug}/session/milestones`}
            className="font-body text-[11.5px] italic text-ink-3 no-underline"
            style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
          >
            See {possessive} Milestones →
          </Link>
        </div>
      </div>
    </div>
  );
}
