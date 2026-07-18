'use client';

// The eight-step shell (mockups 11b–11i): one step per screen, each a quiet
// single-purpose surface rendered from the liturgy's typed elements — this
// component is the one renderer every service shares, whether the steps came
// from a daypart service (/worship) or a devotion (turn 15). Step 5
// (Professing Faith) is the deliberate exception: a hand-off card into the
// untouched session screen (8a), which returns here at the following step
// when the question is answered. Element sources render as a footnote-
// register line, never a card competing with the text being prayed or sung.
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';

import { getActiveLocalCatechismTrack } from '@/lib/localCatechismProgress';
import { getQuestion } from '@/lib/programContent';
import { PROGRAMS, type ProgramDefinition } from '@/lib/programs';
import type { ElementSource, WorshipElement, WorshipStep } from '@/lib/worship';

export interface WorshipShellProps {
  steps: WorshipStep[];
  /** `?step=` navigation builds on this, e.g. /worship/morning */
  baseHref: string;
  /** where ✕ on step 1 leads */
  exitHref: string;
  /** query appended to the catechism hand-off so the session knows the way
   * back, e.g. "worship=morning" or "devotion=psalm-130" */
  handoffQuery: string;
  /** what the catechism-step footer calls this flow: "Family Worship",
   * "this devotion" */
  returnName: string;
  finishHref: string;
  finishLabel: string;
}

interface Handoff {
  program: ProgramDefinition;
  questionNumber: number;
}

function SourceLine({ source }: { source: ElementSource }) {
  const glyph = source.external ? ' ↗' : ' ›';
  return (
    <div className="mt-4 text-center">
      <a
        href={source.href}
        {...(source.external ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
        className="font-body text-[11.5px] italic text-muted no-underline"
        style={{ borderBottom: '1px dotted var(--color-muted)' }}
      >
        {source.label}
        {glyph}
      </a>
    </div>
  );
}

function Lede({ text }: { text: string }) {
  return (
    <>
      <p className="m-0 mb-6 font-body text-[13.5px] italic leading-[1.7] text-ink-2">{text}</p>
      <div className="mx-auto mb-6 h-px w-9 bg-hairline" aria-hidden="true" />
    </>
  );
}

function ElementView({
  element, handoffQuery, handoff,
}: { element: WorshipElement; handoffQuery: string; handoff: Handoff | null }) {
  switch (element.type) {
    case 'scripture':
      return (
        <div>
          {element.lede && <Lede text={element.lede} />}
          <div className="mb-2.5 font-display text-[12.5px] italic text-ink-3">{element.citation}</div>
          <p className="m-0 font-body text-[17px] italic leading-[1.7] text-ink">
            &ldquo;{element.text}&rdquo;
          </p>
          {element.source && <SourceLine source={element.source} />}
        </div>
      );
    case 'prayer':
      return (
        <div>
          {element.lede && <Lede text={element.lede} />}
          <p className="m-0 font-body text-[14.5px] leading-[1.85] text-ink">{element.text}</p>
          {element.amen && (
            <div className="label-caps mt-5.5 text-[11px] tracking-[0.1em] text-ochre">Amen</div>
          )}
          {element.source && <SourceLine source={element.source} />}
        </div>
      );
    case 'song':
    case 'creed':
      return (
        <div>
          {element.lede && <Lede text={element.lede} />}
          <div className="mb-5 font-display text-[15px] font-semibold">{element.title}</div>
          <p className="m-0 whitespace-pre-line font-body text-[17px] italic leading-[2] text-ink">
            {element.type === 'song' ? element.lyrics : element.text}
          </p>
          {element.source && <SourceLine source={element.source} />}
        </div>
      );
    case 'instruction':
      return (
        <div>
          <div className="mx-auto mb-5 h-px w-9 bg-hairline" aria-hidden="true" />
          <p className="m-0 font-body text-[12.5px] italic leading-[1.65] text-ink-2">{element.text}</p>
        </div>
      );
    case 'prompts':
      return (
        <div className="w-full text-left">
          {element.lede && (
            <p className="m-0 mb-4 text-center font-body text-[12.5px] italic leading-[1.6] text-ink-2">
              {element.lede}
            </p>
          )}
          <div className="flex flex-col gap-2.5">
            {element.items.map((item) => (
              <div key={item.label} className="rounded-sm bg-fill px-4 py-3.5">
                <div className="label-caps mb-1 text-[9px] tracking-[0.1em] text-ochre">{item.label}</div>
                <div className="font-body text-[12.5px] italic text-ink">{item.text}</div>
              </div>
            ))}
          </div>
        </div>
      );
    case 'catechism': {
      if (!handoff) return null;
      const question = getQuestion(handoff.program, handoff.questionNumber);
      return (
        <div className="w-full">
          {element.lede && <Lede text={element.lede} />}
          <Link
            href={`/programs/${handoff.program.slug}/session?${handoffQuery}`}
            className="block w-full rounded-sm border border-ochre bg-ochre/10 px-5 py-5.5 text-center text-ink no-underline"
          >
            <div className="label-caps mb-2 text-[9px] tracking-[0.1em] text-ochre">
              Question {handoff.questionNumber} of {handoff.program.totalQuestions}
            </div>
            <div className="font-body text-[15px] italic leading-[1.6] text-ink">
              {question?.question}
            </div>
            <div className="label-caps mt-3.5 text-[10px] tracking-[0.08em] text-ochre">
              Answer Together →
            </div>
          </Link>
        </div>
      );
    }
    default:
      return null;
  }
}

export function WorshipShell({
  steps, baseHref, exitHref, handoffQuery, returnName, finishHref, finishLabel,
}: WorshipShellProps) {
  const searchParams = useSearchParams();
  const requested = Number(searchParams.get('step') ?? '1');

  const totalSteps = steps.length;
  const stepNumber = Number.isInteger(requested)
    ? Math.min(Math.max(requested, 1), totalSteps)
    : 1;
  const step = steps[stepNumber - 1];

  // The hand-off card needs the active track's question; read-only, like the
  // landing — the session itself starts the track when the family answers.
  const [handoff, setHandoff] = useState<Handoff | null>(null);
  useEffect(() => {
    const track = getActiveLocalCatechismTrack();
    const program = (track && PROGRAMS.find((p) => p.contentId === track.catechismId))
      ?? PROGRAMS[0];
    setHandoff({
      program,
      questionNumber: track ? Math.min(track.currentQuestion, program.totalQuestions) : 1,
    });
  }, []);

  const isCatechismStep = step.elements.some((el) => el.type === 'catechism');
  const isPromptsStep = step.elements.some((el) => el.type === 'prompts');

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex items-center justify-between px-6 pt-5">
        {stepNumber === 1 ? (
          <Link href={exitHref} aria-label="Exit worship" className="font-display text-[15px] text-ink no-underline">
            ✕
          </Link>
        ) : (
          <Link
            href={`${baseHref}?step=${stepNumber - 1}`}
            aria-label="Back"
            className="font-display text-[15px] text-ink no-underline"
          >
            ←
          </Link>
        )}
        <div className="flex gap-[5px]" aria-label={`Step ${stepNumber} of ${totalSteps}`}>
          {steps.map((s, i) => (
            <span
              key={s.role}
              className={`h-1.5 w-1.5 rounded-full ${
                i < stepNumber - 1 ? 'bg-ink'
                  : i === stepNumber - 1 ? 'bg-ochre'
                    : 'border border-hairline'
              }`}
              aria-hidden="true"
            />
          ))}
        </div>
        <span className="w-[15px]" aria-hidden="true" />
      </div>

      <div className={`flex flex-1 flex-col items-center px-8 py-6 text-center ${isPromptsStep ? '' : 'justify-center'}`}>
        <div className="label-caps mb-4 text-[9px] tracking-[0.14em] text-ochre">
          Step {stepNumber} · {step.role}
        </div>
        <div className="flex w-full flex-col gap-7">
          {step.elements.map((element, i) => (
            <ElementView key={i} element={element} handoffQuery={handoffQuery} handoff={handoff} />
          ))}
        </div>
      </div>

      <div className="border-t border-hairline px-6 pt-4 pb-9 text-center">
        {isCatechismStep ? (
          <span className="font-body text-[11.5px] italic text-muted">
            {`The question returns to ${returnName} at step ${stepNumber + 1} when you’ve finished`}
          </span>
        ) : stepNumber < totalSteps ? (
          <Link
            href={`${baseHref}?step=${stepNumber + 1}`}
            className="label-caps pb-0.5 text-[11px] tracking-[0.08em] text-ink no-underline"
            style={{ borderBottom: '1px dotted var(--color-ink)' }}
          >
            Continue →
          </Link>
        ) : (
          <Link href={finishHref} className="action-button">
            {finishLabel}
          </Link>
        )}
      </div>
    </div>
  );
}
