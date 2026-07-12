'use client';

// The single "aha" question card (mockup 8a): the catechism answer with every
// clause cited in-line, one clause's proof text shown at a time, and two
// entry points — Pray About This (its own screen, mockup 8b), Resources —
// one tap from the question. This is the one piece of UI a signed-in
// session and a signed-out visitor must never diverge on; only the chrome
// around it (dots, save link, footer) is allowed to differ by entry point.
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';

import { fetchEsvText } from '@/lib/esvClient';
import { entryId as getEntryId, getQuestion, getQuestionCitations } from '@/lib/programContent';
import type { ProgramDefinition } from '@/lib/programs';

// Keeps the "Now Showing" pill on one line at the session frame's mobile
// width (390px, per the mockups — the app locks to this width even on wide
// screens). Measured against that frame: "Now Showing — "…"" chrome plus a
// clause over ~26 characters wraps the pill, so long clauses (e.g. WSC-2's
// "The Word of God, which is contained in the Scriptures of the Old and New
// Testaments") get cut at a word boundary rather than wrapping.
const MAX_CLAUSE_LABEL_LENGTH = 26;

function truncateClause(text: string): string {
  const trimmed = text.trim().replace(/[.,;:]+$/, '');
  if (trimmed.length <= MAX_CLAUSE_LABEL_LENGTH) return trimmed;
  const cut = trimmed.slice(0, MAX_CLAUSE_LABEL_LENGTH);
  const lastSpace = cut.lastIndexOf(' ');
  return `${cut.slice(0, lastSpace > 0 ? lastSpace : MAX_CLAUSE_LABEL_LENGTH)}…`;
}

export function QuestionCard({
  program, questionNumber, childName,
}: { program: ProgramDefinition; questionNumber: number; childName: string }) {
  const question = getQuestion(program, questionNumber);
  // Memoized so its identity is stable across re-renders within the same
  // question — otherwise the reset effect below (keyed on citations.groups)
  // would fire on every click and snap the active clause back to the first.
  const citations = useMemo(() => getQuestionCitations(program, questionNumber), [program, questionNumber]);
  const entryId = getEntryId(program, questionNumber);

  const [activeMarker, setActiveMarker] = useState<string | null>(citations?.groups[0]?.marker ?? null);
  const [verseTexts, setVerseTexts] = useState<Record<string, string | null>>({});
  const [reflection, setReflection] = useState<{ slug: string; title: string } | null>(null);

  useEffect(() => {
    setActiveMarker(citations?.groups[0]?.marker ?? null);
  }, [questionNumber, citations]);

  const activeGroup = citations?.groups.find((g) => g.marker === activeMarker) ?? null;
  const activeSegment = citations?.answerSegments.find((s) => s.marker === activeMarker) ?? null;
  const activeSegmentLabel = activeSegment ? truncateClause(activeSegment.text) : null;

  useEffect(() => {
    activeGroup?.refs.forEach((ref) => {
      if (ref.osis in verseTexts) return;
      fetchEsvText(ref.osis).then((text) => setVerseTexts((prev) => ({ ...prev, [ref.osis]: text })));
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeGroup]);

  useEffect(() => {
    if (!entryId) {
      setReflection(null);
      return;
    }
    let stale = false;
    fetch(`/api/reflection?entryId=${encodeURIComponent(entryId)}`)
      .then((r) => r.json())
      .then((data: { slug: string | null; title: string | null }) => {
        if (!stale) setReflection(data.slug && data.title ? { slug: data.slug, title: data.title } : null);
      })
      .catch(() => {
        if (!stale) setReflection(null);
      });
    return () => {
      stale = true;
    };
  }, [entryId]);

  if (!question) return null;

  return (
    <div className="w-full">
      <blockquote className="m-0 mb-6 font-body text-[18px] italic leading-[1.6] text-ink">
        Q. {question.question}
        <br />
        <br />
        A.{' '}
        {(citations?.answerSegments ?? [{ text: question.answer }]).map((segment, i) => (
          segment.marker ? (
            <span
              key={i}
              role="button"
              tabIndex={0}
              onClick={() => setActiveMarker(segment.marker!)}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') setActiveMarker(segment.marker!); }}
              className={`cursor-pointer rounded-sm ${activeMarker === segment.marker ? 'bg-ochre/10 px-1' : ''}`}
              style={{
                borderBottom: `1px dotted ${activeMarker === segment.marker ? 'var(--color-ochre)' : 'var(--color-ink-3)'}`,
                color: activeMarker === segment.marker ? 'var(--color-ink)' : 'var(--color-ink-3)',
              }}
            >
              {segment.text}
              <sup className="ml-0.5 font-display text-[10px] not-italic text-ochre">{segment.marker}</sup>
            </span>
          ) : <span key={i}>{segment.text}</span>
        ))}
      </blockquote>

      {!!citations?.groups.length && (
        <>
          <div className="label-caps mb-4 text-center text-[9px] tracking-[0.12em] text-ink-3">
            The Scripture Behind It
          </div>
          {citations.groups.length > 1 && activeSegmentLabel && (
            <div className="mb-4 flex justify-center">
              <div className="label-caps inline-flex items-center gap-1.5 rounded-full bg-ochre/10 px-3 py-1.5 text-[9px] tracking-[0.1em] text-ochre">
                <span className="h-1.5 w-1.5 rounded-full bg-ochre" aria-hidden="true" />
                Now Showing — &ldquo;{activeSegmentLabel}&rdquo;
              </div>
            </div>
          )}
          <div className="mb-2 min-h-[100px] text-center">
            {activeGroup?.refs.map((ref) => (
              <div key={ref.osis} className="mb-3 font-body text-[14.5px] italic leading-[1.6] text-ink">
                {verseTexts[ref.osis] ?? '…'}
                <cite className="label-caps mt-2 block text-[10px] not-italic tracking-[0.1em] text-ink-3">
                  {ref.citation}
                </cite>
              </div>
            ))}
          </div>
          {citations.groups.length > 1 && (
            <div className="mb-8 text-center font-body text-[11px] italic text-muted">
              Tap the other phrase above to see its verse
            </div>
          )}
        </>
      )}

      <div className="flex flex-col gap-2.5">
        <Link
          href={`/programs/${program.slug}/prayer/${questionNumber}?child=${encodeURIComponent(childName)}`}
          className="flex items-center gap-3 rounded-sm bg-fill px-3.5 py-3 text-left text-ink no-underline"
        >
          <div className="grow">
            <div className="font-display text-[12.5px] font-semibold text-ink">Pray About This</div>
            <div className="font-body text-[11.5px] italic text-ink-3">
              A short prayer for {childName}, on this question
            </div>
          </div>
          <span className="font-display text-[13px] text-ink-3" aria-hidden="true">›</span>
        </Link>

        {reflection && (
          <>
            <a
              href={`/reflections/${reflection.slug}`}
              className="flex items-center gap-3 rounded-sm bg-fill px-3.5 py-3 text-left text-ink no-underline"
            >
              <div className="grow">
                <div className="font-display text-[12.5px] font-semibold text-ink">Resources</div>
                <div className="font-body text-[11.5px] italic text-ink-3">
                  We&rsquo;ve curated resources to help you understand this question and answer
                </div>
              </div>
              <span className="font-display text-[13px] text-ink-3" aria-hidden="true">›</span>
            </a>
          </>
        )}
      </div>
    </div>
  );
}
