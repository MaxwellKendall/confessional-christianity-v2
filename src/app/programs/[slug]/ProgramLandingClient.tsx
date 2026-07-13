'use client';

// Program landing (mockup 5d). Progress is tracked entirely on this device.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import {
  getLocalCatechismTrack,
  localProgressLabel,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { getProgram } from '@/lib/programs';
import { getQuestion, hasPrayer } from '@/lib/programContent';
import { ProgressBar } from '@/components/ProgressBar';

const CONTENTS_WINDOW = 6;

export function ProgramLandingClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLocalTrack(getLocalCatechismTrack(program.contentId));
    setLoading(false);
  }, [program.contentId]);

  const header = (
    <>
      <div className="px-5 pt-5 label-caps text-[9.5px] tracking-[0.1em]">
        <Link href="/programs" className="dotted-link text-ink-3">Catechisms</Link>
      </div>
      <div className="px-8 pt-4 text-center">
        {program.tradition && (
          <div className="label-caps mb-3 text-[9.5px] text-ink-3">{program.tradition}</div>
        )}
        <h1 className="mb-2 font-display text-[21px] font-semibold leading-[1.3]">
          {program.title}
        </h1>
        <p className="mb-3 text-[13.5px] italic leading-relaxed text-ink-2">
          Each question paired with proof-text Scripture, a closing prayer,
          and progress milestones you can save on this device.
        </p>
        <div className="label-caps text-[10px] tracking-[0.1em] text-ink-3">
          {`~${program.estimatedMinutes} minutes`}
        </div>
      </div>
    </>
  );

  if (loading) return <div>{header}</div>;

  // Completed (5e): a real, acknowledged state with two paths forward.
  if (localTrack && localTrack.currentQuestion > program.totalQuestions) {
    return (
      <div className="flex flex-1 flex-col">
        <div className="px-6 pt-4">
          <Link href="/" aria-label="Back to homepage" className="font-display text-[15px] text-ink no-underline">←</Link>
        </div>
        <div className="flex flex-1 flex-col items-center justify-center px-10 py-16 text-center">
          <div className="mb-5 text-2xl text-ochre" aria-hidden="true">♥</div>
          <div className="label-caps mb-3 text-[9.5px] text-ink-3">
            {program.shortTitle} · Complete
          </div>
          <h1 className="mb-3.5 font-display text-xl font-semibold leading-[1.4]">
            All {program.totalQuestions} Questions of the {program.shortTitle}
          </h1>
          <p className="text-[13.5px] italic leading-[1.7] text-ink-2">
            Every question has been recited, start to finish. Nothing here is
            lost — the history stays exactly as it is.
          </p>
        </div>
        <div className="flex flex-col items-center gap-4 px-6 pb-11">
          <Link href="/programs" className="dotted-link text-[13px] italic text-ink-2">
            Start Another Catechism
          </Link>
        </div>
      </div>
    );
  }

  const visibleCurrentQuestion = localTrack?.currentQuestion ?? 1;
  const contentsStart = localTrack
    ? Math.max(1, Math.min(visibleCurrentQuestion - 3, program.totalQuestions - CONTENTS_WINDOW + 1))
    : 1;
  const contentsNumbers = Array.from({ length: CONTENTS_WINDOW }, (_, i) => contentsStart + i)
    .filter((n) => n <= program.totalQuestions);

  return (
    <div className="pb-7">
      {header}

      {localTrack ? (
        <div className="mx-5 mt-6 border-t border-hairline pt-4 text-center">
          <div className="mb-3 font-display text-[17px] font-semibold">Continue the {program.shortTitle}</div>
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
            Continue the {program.shortTitle} →
          </Link>
        </div>
      ) : (
        <div className="mx-5 mt-6 border-t border-hairline pt-5 text-center">
          <Link href={`/programs/${slug}/start`} className="action-button">
            Begin with a Starting Question
          </Link>
          <p className="mt-3 text-[12.5px] italic text-ink-2">
            No account required. Progress saves on this device.
          </p>
        </div>
      )}

      <div className="mx-5 mt-6 border-t border-hairline pt-4">
        <div className="label-caps mb-2 text-[9.5px] text-ink-3">Contents</div>
        <div className="flex flex-col">
          {contentsNumbers.map((n) => {
            const q = getQuestion(program, n);
            const isCurrent = n === visibleCurrentQuestion;
            return (
              <Link
                key={n}
                href={`/programs/${slug}/session?start=${n}`}
                className="group flex items-center justify-between gap-3 border-t border-hairline py-2.5 no-underline last:border-b"
              >
                <div>
                  <div className={`font-display text-[13px] font-semibold ${isCurrent ? 'text-ink' : 'text-ink-2'} group-hover:text-ink`}>
                    Q. {n} — {q?.question}
                  </div>
                  {!hasPrayer(program, n) && (
                    <div className="mt-0.5 text-[10.5px] italic text-heart-reviewing">
                      Prayer not yet written
                    </div>
                  )}
                </div>
                <span aria-hidden="true" className="shrink-0 font-display text-[13px] text-ink-3 group-hover:text-ink">
                  →
                </span>
              </Link>
            );
          })}
        </div>
      </div>
    </div>
  );
}
