'use client';

// Homepage (mockup 6c + PRD §8): one child's context at a time via the
// circular avatar switcher — tapping another child's avatar goes straight
// into that child's session; the continue card has no button, the whole card
// is the tap target.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { getActiveChildId, setActiveChildId } from '@/lib/activeChild';
import { PROGRAMS } from '@/lib/programs';
import { ProgressBar } from './ProgressBar';
import type { ChildWithRole } from '@/lib/database.types';

const AVATAR_CLASSES = ['bg-avatar-1', 'bg-avatar-2', 'bg-avatar-3'];

const PROGRAM = PROGRAMS[0];

export interface HomeReflection {
  slug: string;
  title: string;
  author: string | null;
  dateShort: string;
}

function SupportingSections({ reflections }: { reflections: HomeReflection[] }) {
  return (
    <>
      <div className="mx-5 mt-6 border-t border-hairline pt-4">
        <div className="mb-2.5 flex items-baseline justify-between">
          <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">Programs</div>
          <Link href="/programs" className="label-caps dotted-link text-[9.5px] tracking-[0.1em] text-ink-3">
            See All
          </Link>
        </div>
        <Link href={`/programs/${PROGRAM.slug}`} className="block py-2.5 text-ink no-underline">
          <div className="mb-1 font-display text-sm font-semibold">{PROGRAM.title}</div>
          <div className="text-xs leading-relaxed text-ink-2">{PROGRAM.description}</div>
        </Link>
      </div>

      {reflections.length > 0 && (
        <div className="mx-5 mt-5 border-t border-hairline pt-4">
          <div className="mb-2.5 flex items-baseline justify-between">
            <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">Latest Reflections</div>
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
  const { user, loading: authLoading } = useAuth();
  const { children, loading: childrenLoading } = useChildren();
  const router = useRouter();
  const [activeId, setActiveId] = useState<string | null>(null);

  useEffect(() => {
    if (!children.length) return;
    const stored = getActiveChildId();
    setActiveId(children.some((c) => c.id === stored) ? stored : children[0].id);
  }, [children]);

  const loading = authLoading || childrenLoading;
  const activeChild = children.find((c) => c.id === activeId) ?? null;
  const assignment = activeChild?.catechism_assignments
    ?.find((a) => a.catechism_id === PROGRAM.catechismId) ?? null;

  const switchChild = (child: ChildWithRole) => {
    setActiveChildId(child.id);
    setActiveId(child.id);
    // one tap, straight into that child's session (6c)
    if (child.id !== activeId) {
      router.push(`/programs/${PROGRAM.slug}/session`);
    }
  };

  if (loading) {
    return <div className="min-h-40" aria-hidden="true" />;
  }

  // No account or no children yet: the same page still leads with Programs
  // (PRD §8), never an essay masthead.
  if (!user || children.length === 0) {
    return (
      <div>
        <div className="px-6 pt-9 text-center">
          <div className="label-caps mb-3 text-[9.5px] text-ink-3">Family Catechesis</div>
          <h1 className="font-display text-xl font-semibold leading-snug">
            Catechize Your Child, One Question at a Time
          </h1>
          <p className="mx-auto mt-3 max-w-[26rem] text-[13.5px] italic leading-relaxed text-ink-2">
            A paced walk through a historic catechism — each question with its
            own scripture and a prayer to close.
          </p>
          <Link
            href={user ? '/onboarding/child' : '/auth/signup'}
            className="action-button mx-auto mt-6 max-w-72"
          >
            {user ? 'Add a Child to Begin' : 'Start a Program'}
          </Link>
          {!user && (
            <div className="mt-4 text-[13px] italic text-ink-2">
              Already have an account?{' '}
              <Link href="/auth/signin" className="dotted-link text-ink">Sign in</Link>
            </div>
          )}
        </div>
        <SupportingSections reflections={reflections} />
      </div>
    );
  }

  return (
    <div>
      <div className="px-6 pt-6">
        <div className="mb-6 flex items-center justify-center gap-3.5">
          {children.map((child, i) => (
            child.id === activeId ? (
              <div
                key={child.id}
                role="button"
                aria-current="true"
                aria-label={child.name}
                className={`flex h-10 w-10 items-center justify-center rounded-full font-display text-sm text-card ${AVATAR_CLASSES[i % AVATAR_CLASSES.length]}`}
                style={{ boxShadow: '0 0 0 2px var(--color-card), 0 0 0 3.5px var(--color-ink)' }}
              >
                {child.name[0]?.toUpperCase()}
              </div>
            ) : (
              <button
                key={child.id}
                type="button"
                aria-label={`Jump straight to ${child.name}’s session`}
                onClick={() => switchChild(child)}
                className={`flex h-10 w-10 cursor-pointer items-center justify-center rounded-full border-none font-display text-sm text-card ${AVATAR_CLASSES[i % AVATAR_CLASSES.length]}`}
              >
                {child.name[0]?.toUpperCase()}
              </button>
            )
          ))}
          <Link
            href="/onboarding/child"
            aria-label="Add a child"
            className="flex h-10 w-10 items-center justify-center rounded-full border border-dotted border-muted font-display text-base text-muted no-underline"
          >
            +
          </Link>
        </div>

        <div className="label-caps mb-3.5 text-center text-[9.5px] text-ink-3">
          Continue Where You Left Off
        </div>

        {activeChild && assignment ? (
          <Link
            href={`/programs/${PROGRAM.slug}/session`}
            className="block rounded-[2px] bg-fill px-5 pt-5 pb-[18px] text-inherit no-underline"
          >
            <div className="mb-1.5 font-display text-[14.5px] font-semibold text-ink">
              {activeChild.name}’s Plan
            </div>
            <div className="mb-2.5 text-[13px] italic text-ink-2">The Shorter Catechism</div>
            <div className="mb-1.5 flex items-baseline justify-between">
              <span className="label-caps-sm text-[9px] text-ink-3">
                Q. {Math.min(assignment.current_question, PROGRAM.totalQuestions)} of {PROGRAM.totalQuestions}
              </span>
            </div>
            <ProgressBar fraction={(assignment.current_question - 1) / PROGRAM.totalQuestions} />
          </Link>
        ) : activeChild && (
          <Link
            href={`/programs/${PROGRAM.slug}/start`}
            className="block rounded-[2px] bg-fill px-5 pt-5 pb-[18px] text-inherit no-underline"
          >
            <div className="mb-1.5 font-display text-[14.5px] font-semibold text-ink">
              Start a Plan for {activeChild.name}
            </div>
            <div className="text-[13px] italic text-ink-2">
              The Shorter Catechism — each question with its scripture and a prayer.
            </div>
          </Link>
        )}
      </div>

      <SupportingSections reflections={reflections} />
    </div>
  );
}
