'use client';

// Resources on the current question (mockup 10a): a list filterable by kind,
// where each row's icon, meta line, and trailing glyph signal what tapping it
// will do before you tap — ↗ leaves for the platform hosting the resource
// (Spotify, YouTube, Amazon, a publication), › stays in the app (original
// writing opens its reflection, mockup 10b).
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';

import { useSessionTrack } from '@/hooks/useSessionTrack';
import { entryId as getEntryId, getQuestion } from '@/lib/programContent';
import { getProgram } from '@/lib/programs';
import { RESOURCE_KIND_LABELS, RESOURCE_KINDS, type ResourceKind } from '@/lib/resourceKinds';
import type { Resource } from '@/lib/resources';

function KindIcon({ kind }: { kind: ResourceKind }) {
  if (kind === 'book') {
    return (
      <div
        className="relative h-11 w-8 shrink-0 border border-muted bg-fill"
        aria-hidden="true"
      >
        <div className="absolute inset-y-0 left-0 w-1 bg-ink-3" />
      </div>
    );
  }
  const glyph = {
    song: (
      <svg width="12" height="13" viewBox="0 0 12 13"><path d="M1 1l10 5.5L1 12z" fill="currentColor" /></svg>
    ),
    podcast: (
      <svg width="14" height="13" viewBox="0 0 14 13">
        <line x1="1.5" y1="8" x2="1.5" y2="11" stroke="currentColor" strokeWidth="1.4" />
        <line x1="5.5" y1="3" x2="5.5" y2="11" stroke="currentColor" strokeWidth="1.4" />
        <line x1="9.5" y1="5.5" x2="9.5" y2="11" stroke="currentColor" strokeWidth="1.4" />
        <line x1="13" y1="1.5" x2="13" y2="11" stroke="currentColor" strokeWidth="1.4" />
      </svg>
    ),
    essay: (
      <svg width="13" height="13" viewBox="0 0 13 13">
        <line x1="1" y1="2.5" x2="12" y2="2.5" stroke="currentColor" strokeWidth="1.2" />
        <line x1="1" y1="6.5" x2="12" y2="6.5" stroke="currentColor" strokeWidth="1.2" />
        <line x1="1" y1="10.5" x2="8" y2="10.5" stroke="currentColor" strokeWidth="1.2" />
      </svg>
    ),
    original: (
      <svg width="13" height="13" viewBox="0 0 13 13">
        <circle cx="6.5" cy="6.5" r="5.5" fill="none" stroke="currentColor" strokeWidth="1.3" />
        <circle cx="6.5" cy="6.5" r="1.6" fill="currentColor" />
      </svg>
    ),
  }[kind];
  return (
    <div
      className={`flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-full bg-card ${kind === 'original' ? 'border border-ochre text-ochre' : 'border border-hairline text-ink-3'}`}
      aria-hidden="true"
    >
      {glyph}
    </div>
  );
}

function ResourceRow({ resource }: { resource: Resource }) {
  const inApp = resource.kind === 'original';
  const body = (
    <>
      <KindIcon kind={resource.kind} />
      <div className="min-w-0 grow">
        <div className="label-caps mb-0.5 text-[8.5px] tracking-[0.1em] text-ochre">
          {RESOURCE_KIND_LABELS[resource.kind].row}
        </div>
        <div className="font-display text-[13px] font-semibold text-ink">{resource.title}</div>
        {resource.meta && (
          <div className="font-body text-[11.5px] italic text-ink-3">{resource.meta}</div>
        )}
      </div>
      <span className="shrink-0 font-display text-[13px] text-ink-3" aria-hidden="true">
        {inApp ? '›' : '↗'}
      </span>
    </>
  );
  const rowClass = `flex items-center gap-3 rounded-sm px-3.5 py-3.5 text-ink no-underline ${inApp ? 'bg-ochre/10' : 'bg-fill'}`;
  return inApp ? (
    <Link href={`/reflections/${resource.reflectionSlug}`} className={rowClass}>{body}</Link>
  ) : (
    <a href={resource.url!} target="_blank" rel="noopener noreferrer" className={rowClass}>
      {body}
    </a>
  );
}

export function ResourcesClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const track = useSessionTrack(program);
  const questionNumber = track.questionNumber;

  const question = questionNumber ? getQuestion(program, questionNumber) : null;
  const entryId = questionNumber ? getEntryId(program, questionNumber) : null;

  const [resources, setResources] = useState<Resource[] | null>(null);
  const [activeKind, setActiveKind] = useState<ResourceKind | 'all'>('all');

  useEffect(() => {
    if (!entryId) return undefined;
    let stale = false;
    fetch(`/api/resources?entryId=${encodeURIComponent(entryId)}`)
      .then((r) => r.json())
      .then((data: { resources: Resource[] }) => {
        if (!stale) setResources(data.resources ?? []);
      })
      .catch(() => {
        if (!stale) setResources([]);
      });
    return () => {
      stale = true;
    };
  }, [entryId]);

  // Chips only for kinds this question actually has — a filter with nothing
  // behind it is a dead end, not a signal.
  const presentKinds = useMemo(
    () => RESOURCE_KINDS.filter((kind) => resources?.some((r) => r.kind === kind)),
    [resources],
  );
  const visible = resources?.filter((r) => activeKind === 'all' || r.kind === activeKind) ?? [];

  if (track.loading || !question || resources === null) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex items-center justify-between px-6 pt-5">
        <Link
          href={`/programs/${slug}/session`}
          aria-label="Back to the question"
          className="font-display text-[15px] text-ink no-underline"
        >
          ←
        </Link>
        <Link
          href={`/programs/${slug}/session/jump`}
          aria-label="Jump to a different question"
          className="label-caps pb-px text-[9.5px] tracking-[0.12em] text-ochre no-underline"
          style={{ borderBottom: '1px dotted var(--color-ochre)' }}
        >
          Question {questionNumber} of {track.totalQuestions}
        </Link>
      </div>

      <div className="px-6 pt-4 text-center">
        <div className="label-caps text-[9px] tracking-[0.14em] text-ink-3">
          Resources on &ldquo;{question.question.replace(/\?$/, '')}&rdquo;
        </div>
      </div>

      {presentKinds.length > 1 && (
        <div className="flex gap-2 overflow-x-auto pl-6 pt-3.5" role="group" aria-label="Filter by kind">
          {(['all', ...presentKinds] as const).map((kind) => {
            const active = activeKind === kind;
            const ochreChip = kind === 'original' && !active;
            return (
              <button
                key={kind}
                type="button"
                onClick={() => setActiveKind(kind)}
                aria-pressed={active}
                className={`label-caps shrink-0 cursor-pointer rounded-full px-3.5 py-1.5 text-[10px] tracking-[0.08em] ${
                  active
                    ? 'border border-ink bg-ink text-card'
                    : `border bg-transparent ${ochreChip ? 'border-ochre text-ochre' : 'border-hairline text-ink-2'}`
                }`}
              >
                {kind === 'all' ? 'All' : RESOURCE_KIND_LABELS[kind].chip}
              </button>
            );
          })}
          <span className="w-2 shrink-0" aria-hidden="true" />
        </div>
      )}

      <div className="flex flex-1 flex-col gap-2.5 px-6 pt-4 pb-6">
        {visible.map((resource) => (
          <ResourceRow key={`${resource.kind}-${resource.title}`} resource={resource} />
        ))}
        {visible.length === 0 && (
          <p className="pt-8 text-center text-[13px] italic text-ink-2">
            Nothing curated for this question yet.
          </p>
        )}
      </div>

      <div className="px-6 pb-10 text-center">
        <Link
          href={`/programs/${slug}/session`}
          className="font-body text-[12.5px] italic text-ink-3 no-underline"
          style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
        >
          Back to the Question
        </Link>
      </div>
    </div>
  );
}
