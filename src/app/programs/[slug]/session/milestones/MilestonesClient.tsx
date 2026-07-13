'use client';

// Milestones (mockup 9a, turn 9): replaces the old paced review wizard.
// Age-labeled checkpoints reached by position alone — no schedule, no
// steps. One tap off the session screen ("See {name}'s Milestones →"),
// not a step inside it.
import Link from 'next/link';

import { useSessionTrack } from '@/hooks/useSessionTrack';
import { milestoneProgress, milestonesFor, type MilestoneProgress } from '@/lib/milestones';
import { getProgram } from '@/lib/programs';

function captionFor(m: MilestoneProgress): string {
  if (m.state === 'complete') return 'Reached';
  if (m.state === 'in_progress') {
    const base = `${m.seenCount} of ${m.total} questions`;
    return m.typicalAge ? `${base} · typical for age ${m.typicalAge[0]}–${m.typicalAge[1]}` : base;
  }
  return m.typicalAge ? `Typical for age ${m.typicalAge[0]}–${m.typicalAge[1]}` : 'Not yet reached';
}

function MilestoneCircle({ m }: { m: MilestoneProgress }) {
  if (m.state === 'complete') {
    return (
      <div className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full bg-ochre text-xs text-card">
        ✓
      </div>
    );
  }
  if (m.state === 'in_progress') {
    return (
      <div className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full border-[1.5px] border-ochre">
        <div className="h-[9px] w-[9px] rounded-full bg-ochre" />
      </div>
    );
  }
  return (
    <div className="h-[22px] w-[22px] shrink-0 rounded-full border-[1.5px] border-dashed border-muted" />
  );
}

export function MilestonesClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const track = useSessionTrack(program);
  const definitions = milestonesFor(slug);

  if (track.loading) {
    return <div className="min-h-64" aria-hidden="true" />;
  }

  const progress = milestoneProgress(definitions, track.questionNumber ?? track.totalQuestions + 1);
  const possessive = track.childName ? `${track.childName}’s` : 'Your';

  return (
    <div className="min-h-[calc(100dvh-4rem)] pb-10">
      <div className="flex items-center px-5 pt-5 pb-4">
        <Link
          href={`/programs/${slug}/session`}
          aria-label="Back to the question"
          className="font-display text-[15px] text-ink no-underline"
        >
          ←
        </Link>
        <span className="w-[15px]" aria-hidden="true" />
      </div>

      <div className="px-6 pb-2 text-center">
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ink-3">
          {track.childName ?? 'Milestones'}
          {track.childAge !== null ? ` · Age ${track.childAge}` : ''}
        </div>
        <h1 className="mt-1.5 font-display text-[19px] font-semibold">Milestones</h1>
      </div>

      {progress.length === 0 ? (
        <p className="px-9 pt-8 text-center text-[13px] italic leading-relaxed text-ink-2">
          Milestones haven’t been mapped for {possessive.toLowerCase()} catechism yet.
        </p>
      ) : (
        <div className="mt-4 flex flex-col gap-2.5 px-6">
          {progress.map((m) => (
            <div
              key={m.id}
              className={`flex items-start gap-3.5 rounded-sm p-4 ${m.state === 'complete' ? 'bg-ochre/10' : 'bg-fill'} ${m.state === 'locked' ? 'opacity-55' : ''}`}
            >
              <MilestoneCircle m={m} />
              <div>
                <div className="font-display text-[13.5px] font-semibold text-ink">{m.title}</div>
                <div className="mt-0.5 font-body text-[12.5px] italic leading-snug text-ink-3">
                  {captionFor(m)}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
