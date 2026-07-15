'use client';

// Homepage: a plain landing with one button in — no name/age capture, no
// auto-redirect. Progress lives on this device.
import Link from 'next/link';
import { useEffect, useState } from 'react';

import {
  getActiveLocalCatechismTrack,
  localProgressLabel,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
import { PROGRAMS } from '@/lib/programs';

// With no saved progress the homepage pitches the flagship program (WSC).
const DEFAULT_PROGRAM = PROGRAMS[0];

export interface HomeReflection {
  slug: string;
  title: string;
  author: string | null;
  dateShort: string;
}

function SupportingSections({ reflections }: { reflections: HomeReflection[] }) {
  return (
    <>
      {reflections.length > 0 && (
        <div className="mx-5 mt-6 border-t border-hairline pt-4">
          <div className="mb-2.5 flex items-baseline justify-between">
            <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">Latest Resources</div>
            <Link href="/reflections" className="label-caps dotted-link text-[9.5px] tracking-[0.1em] text-ink-3">
              See All
            </Link>
          </div>
          {reflections.map((post) => (
            <Link key={post.slug} href={`/reflections/${post.slug}`} className="block py-2.5 text-ink no-underline">
              <div className="font-display text-[13.5px] font-semibold">{post.title}</div>
              <div className="label-caps mt-1 text-[9px] tracking-[0.1em] text-ink-3">
                {[post.author, post.dateShort].filter(Boolean).join(' · ')}
              </div>
            </Link>
          ))}
        </div>
      )}

      <div className="mx-5 mt-5 mb-7 border-t border-hairline pt-4 text-center">
        <span className="text-[13px] italic text-ink-2">
          Or explore the confessions and catechisms directly in the{' '}
          <Link href="/library" className="dotted-link text-ink">Library</Link>.
        </span>
      </div>
    </>
  );
}

export function HomeClient({ reflections }: { reflections: HomeReflection[] }) {
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setLocalTrack(getActiveLocalCatechismTrack());
    setReady(true);
  }, []);

  if (!ready) {
    return <div className="min-h-40" aria-hidden="true" />;
  }

  // A track whose catechism no longer maps to a program can't be continued;
  // treat it as a fresh visit.
  const trackProgram = localTrack
    ? PROGRAMS.find((p) => p.contentId === localTrack.catechismId) ?? null
    : null;
  const track = trackProgram ? localTrack : null;
  const program = trackProgram ?? DEFAULT_PROGRAM;

  return (
    <div>
      <div className="px-8 pt-9 text-center">
        <div className="label-caps mb-3 text-[9.5px] text-ink-3">For your child</div>
        <h1 className="mb-2 font-display text-xl font-semibold leading-snug">
          {program.title}
        </h1>
        <p className="mb-6 text-[13px] italic leading-relaxed text-ink-2">
          {program.description}
        </p>
        <Link href="/worship" className="action-button mx-auto max-w-72">
          Begin Family Worship
        </Link>
        <div className="mt-3.5">
          <Link
            href={`/programs/${program.slug}/session`}
            className="font-body text-[12px] italic text-ink-3 no-underline"
            style={{ borderBottom: '1px dotted var(--color-ink-3)' }}
          >
            {track
              ? `Just answer today’s question — continue Question ${Math.min(track.currentQuestion, program.totalQuestions)} →`
              : 'Just answer today’s question →'}
          </Link>
        </div>
        {track && (
          <div className="label-caps mt-3 text-[9px] tracking-[0.1em] text-ink-3">
            {localProgressLabel}
          </div>
        )}
      </div>
      <SupportingSections reflections={reflections} />
    </div>
  );
}
