'use client';

// Homepage: two cards and a browse row — Continue the WSC devotion run (turn
// 17), the active catechism session with its progress bar, then the other
// catechisms. Family Worship (turn 11) was the aspirational placeholder
// before there was real cumulative content; now that the WSC run spans 53
// days of authored devotions, it leads instead — a real arc to move through,
// not the same eight-step shape every day. No name/age capture, no
// auto-redirect; progress lives on this device. Base sizes serve the phone
// frame; the sm: step matches the full-bleed shell.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import { seriesForCatechism } from '@/lib/devotionSeries';
import {
  getActiveLocalCatechismTrack,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { currentPartDay, getSeriesCompletedDays } from '@/lib/localSeriesProgress';
import { PROGRAMS } from '@/lib/programs';

// With no saved progress the homepage pitches the flagship program (WSC).
const DEFAULT_PROGRAM = PROGRAMS[0];
const WSC_RUN = seriesForCatechism('WSC');

export function HomeClient() {
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);
  const [runCompleted, setRunCompleted] = useState<number[] | null>(null);

  // The saved track and the run's local progress are both device state, so
  // neither can render on the server; the mount effect doubles as the ready
  // gate.
  useEffect(() => {
    setLocalTrack(getActiveLocalCatechismTrack());
    setRunCompleted(WSC_RUN ? getSeriesCompletedDays(WSC_RUN.slug) : []);
  }, []);

  if (!runCompleted) {
    return <div className="min-h-40" aria-hidden="true" />;
  }

  // A track whose catechism no longer maps to a program can't be continued;
  // treat it as a fresh visit.
  const trackProgram = localTrack
    ? PROGRAMS.find((p) => p.contentId === localTrack.catechismId) ?? null
    : null;
  const track = trackProgram ? localTrack : null;
  const program = trackProgram ?? DEFAULT_PROGRAM;

  const questionNumber = track
    ? Math.min(track.currentQuestion, program.totalQuestions)
    : 1;
  const progressPct = ((questionNumber - 1) / program.totalQuestions) * 100;
  const otherPrograms = PROGRAMS.filter((p) => p.slug !== program.slug);

  const runTotal = WSC_RUN?.parts.length ?? 0;
  const currentDay = WSC_RUN ? currentPartDay(runCompleted, runTotal) : null;
  const currentPart = currentDay ? WSC_RUN?.parts.find((p) => p.day === currentDay) ?? null : null;

  return (
    <div className="mx-auto w-full max-w-5xl px-5 pt-7 pb-10 sm:px-10 sm:pt-12 sm:pb-16">
      {WSC_RUN && (
        <Link
          href={`/devotions/${WSC_RUN.slug}`}
          className="block rounded-sm bg-fill px-6 py-6 text-ink no-underline sm:px-10 sm:py-9"
        >
          <div className="label-caps mb-2.5 text-[9.5px] tracking-[0.14em] text-ochre sm:mb-3.5 sm:text-[11.5px]">
            {currentDay === null
              ? `All ${runTotal} Parts Complete`
              : `Part ${currentDay} of ${runTotal} · Westminster Shorter Catechism`}
          </div>
          <div className="flex items-baseline justify-between gap-4">
            <h1 className="m-0 heading-page">
              {currentDay === null ? 'The Whole Catechism, Professed'
                : runCompleted.length > 0 ? `Continue — Part ${currentDay}`
                  : 'Begin — Part 1'}
            </h1>
            <span className="font-display text-[18px] text-ochre sm:text-[20px]" aria-hidden="true">→</span>
          </div>
          <p className="m-0 mt-1.5 font-body text-[13px] italic text-ink-2 sm:mt-2.5 sm:text-[15.5px]">
            {currentPart ? `${currentPart.title} (${currentPart.citation})` : 'Beginning to end, in order'}
          </p>
        </Link>
      )}

      {/* the devotions library's entry point (12a): a quiet alternative to
          the WSC run card, never competing with it */}
      <div className="mt-3.5 text-center sm:mt-5">
        <Link
          href="/devotions"
          className="dotted-link font-body text-[12px] italic text-ink-3 sm:text-[14px]"
        >
          Or choose today&rsquo;s devotion →
        </Link>
      </div>

      <div className="mt-8 sm:mt-12">
        <div className="label-caps mb-2.5 text-[9.5px] tracking-[0.14em] text-ink-3 sm:mb-3.5 sm:text-[11px]">
          Your Catechism
        </div>
        <Link
          href={`/programs/${program.slug}/session`}
          className="block rounded-sm bg-fill px-6 py-5.5 text-ink no-underline sm:px-10 sm:py-8"
        >
          <div className="heading-section">
            {program.title}
          </div>
          <div className="label-caps mt-2 text-[9.5px] tracking-[0.12em] text-ink-3 sm:mt-3 sm:text-[11px]">
            Q. {questionNumber} of {program.totalQuestions}
          </div>
          <div className="mt-2.5 h-[3px] w-full bg-hairline sm:mt-3.5 sm:h-1" aria-hidden="true">
            <div className="h-full bg-ochre" style={{ width: `${progressPct}%` }} />
          </div>
        </Link>
      </div>

      <div className="mt-8 sm:mt-12">
        <div className="label-caps mb-2.5 text-[9.5px] tracking-[0.14em] text-ink-3 sm:mb-3.5 sm:text-[11px]">
          Explore Other Catechisms
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-5">
          {otherPrograms.map((p) => (
            <Link
              key={p.slug}
              href={`/programs/${p.slug}`}
              className="block rounded-sm bg-fill px-5 py-5 text-ink no-underline sm:px-7 sm:py-7"
            >
              <div className="font-display text-[14px] font-semibold leading-snug sm:text-[15.5px]">
                {p.shortTitle}
              </div>
              <div className="label-caps mt-1.5 text-[9px] tracking-[0.1em] text-ink-3 sm:mt-2.5 sm:text-[10.5px]">
                {`${p.totalQuestions} Q&A`}
              </div>
            </Link>
          ))}
        </div>
      </div>

      <div className="mt-9 border-t border-hairline pt-5 text-center sm:mt-14 sm:pt-7">
        <span className="text-[13px] italic text-ink-2 sm:text-[15px]">
          Or explore the confessions and catechisms directly in the{' '}
          <Link href="/library" className="dotted-link text-ink">Library</Link>.
        </span>
      </div>
    </div>
  );
}
