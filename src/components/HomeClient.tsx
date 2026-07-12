'use client';

// Homepage. Signed in (mockup 7e): one child's context at a time via the
// circular avatar switcher — tapping another child's avatar goes straight
// into that child's session; the continue card has no button, the whole card
// is the tap target. Signed out (mockup 7b): one held screen asking only the
// child's name and age, then straight to the first question — no account
// wall anywhere before the save gate.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { getActiveChildId, setActiveChildId } from '@/lib/activeChild';
import {
  DEFAULT_LEARNER_NAME,
  getLocalCatechismTrack,
  getLocalLearner,
  localProgressLabel,
  setLocalLearner,
  startLocalCatechismTrack,
  type LocalCatechismTrack,
} from '@/lib/localCatechismProgress';
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

function SupportingSections({
  reflections,
  showCatechisms = true,
}: {
  reflections: HomeReflection[];
  showCatechisms?: boolean;
}) {
  return (
    <>
      {showCatechisms && (
        <div className="mx-5 mt-6 border-t border-hairline pt-4">
          <div className="mb-2.5 flex items-baseline justify-between">
            <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">Catechisms</div>
            <Link href="/programs" className="label-caps dotted-link text-[9.5px] tracking-[0.1em] text-ink-3">
              See All
            </Link>
          </div>
          {PROGRAMS.map((program) => (
            <Link key={program.slug} href={`/programs/${program.slug}`} className="block py-2.5 text-ink no-underline">
              <div className="mb-1 font-display text-sm font-semibold">{program.title}</div>
              <div className="text-xs leading-relaxed text-ink-2">{program.description}</div>
            </Link>
          ))}
        </div>
      )}

      {reflections.length > 0 && (
        <div className="mx-5 mt-5 border-t border-hairline pt-4">
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

// Mockup 7b: name + age, nothing else, then straight to the first question.
// Deviation flagged to product: the mockup's under-8 note recommends "A
// Catechism for Girls and Boys," which isn't available yet — the note here
// ties to what the age actually does (one new question per session).
function GuestLanding() {
  const router = useRouter();
  const [name, setName] = useState('');
  const [age, setAge] = useState('');

  const parsedAge = /^\d+$/.test(age.trim()) ? Number(age.trim()) : null;
  const trimmedName = name.trim();

  const begin = (e: React.FormEvent) => {
    e.preventDefault();
    if (!trimmedName) return;
    setLocalLearner(trimmedName, parsedAge);
    if (!getLocalCatechismTrack(PROGRAM.contentId)) {
      startLocalCatechismTrack(PROGRAM.contentId, 1);
    }
    router.push(`/programs/${PROGRAM.slug}/session`);
  };

  return (
    <div className="flex min-h-[calc(100dvh-9rem)] flex-col">
      <form
        onSubmit={begin}
        className="flex flex-1 flex-col items-center justify-center px-10 text-center"
      >
        <div className="label-caps mb-[18px] text-[10px] tracking-[0.14em] text-ochre">
          For your child
        </div>
        <h1 className="mb-6 font-body text-[22px] font-normal italic leading-[1.5] text-ink">
          What’s your child’s name and age?
        </h1>
        <div className="mb-4 flex w-full max-w-96 gap-2.5">
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            aria-label="Child’s name"
            placeholder="Name"
            required
            className="min-w-0 flex-1 rounded-[2px] border border-hairline bg-white px-4 py-3.5 text-left font-body text-sm italic text-ink outline-none placeholder:text-ink-3"
          />
          <input
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            value={age}
            onChange={(e) => setAge(e.target.value)}
            aria-label="Child’s age"
            placeholder="Age"
            className="w-[76px] rounded-[2px] border border-hairline bg-white px-4 py-3.5 text-left font-body text-sm italic text-ink outline-none placeholder:text-ink-3"
          />
        </div>
        {parsedAge !== null && parsedAge < 8 && (
          <div className="label-caps mb-4 w-full max-w-96 text-left text-[9.5px] tracking-[0.08em] text-ochre">
            Since {trimmedName || 'your child'} is under 8, we’ll take it
            gently — one new question per session
          </div>
        )}
        <button type="submit" className="action-button-solid w-full max-w-96 cursor-pointer">
          See {trimmedName ? `${trimmedName}’s` : 'the'} First Question →
        </button>
      </form>

      <div className="px-6 pb-8 pt-5 text-center">
        <span className="text-[12.5px] italic text-ink-3">
          Already started?{' '}
          <Link href="/auth/signin" className="dotted-link text-ink">Sign in</Link>
        </span>
      </div>
    </div>
  );
}

export function HomeClient({ reflections }: { reflections: HomeReflection[] }) {
  const { user, loading: authLoading } = useAuth();
  const { children, loading: childrenLoading } = useChildren();
  const router = useRouter();
  const [activeId, setActiveId] = useState<string | null>(null);
  const [localTrack, setLocalTrack] = useState<LocalCatechismTrack | null>(null);
  const [learnerName, setLearnerName] = useState<string | null>(null);
  const [localReady, setLocalReady] = useState(false);

  useEffect(() => {
    if (!children.length) return;
    const stored = getActiveChildId();
    setActiveId(children.some((c) => c.id === stored) ? stored : children[0].id);
  }, [children]);

  useEffect(() => {
    if (authLoading || user) return;
    setLocalTrack(getLocalCatechismTrack(PROGRAM.contentId));
    const learner = getLocalLearner();
    setLearnerName(learner.name === DEFAULT_LEARNER_NAME ? null : learner.name);
    setLocalReady(true);
  }, [authLoading, user]);

  const loading = authLoading || childrenLoading;
  const activeChild = children.find((c) => c.id === activeId) ?? null;
  const assignment = activeChild?.catechism_assignments
    ?.find((a) => a.catechism_id === PROGRAM.contentId) ?? null;
  const otherPrograms = PROGRAMS.filter((p) => p.slug !== PROGRAM.slug);

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

  // Signed out, nothing started: 7b — one held screen, name and age only.
  if (!user && !localReady) {
    return <div className="min-h-40" aria-hidden="true" />;
  }
  if (!user && !localTrack) {
    return <GuestLanding />;
  }

  // Signed out with a track on this device: continue where they left off.
  if (!user) {
    return (
      <div>
        <div className="px-6 pt-9 text-center">
          <div className="label-caps mb-3 text-[9.5px] text-ink-3">For your child</div>
          <h1 className="font-display text-xl font-semibold leading-snug">
            {learnerName ? `${learnerName}’s Shorter Catechism` : 'The Shorter Catechism'}
          </h1>
          <Link
            href={`/programs/${PROGRAM.slug}/session`}
            className="action-button mx-auto mt-6 max-w-72"
          >
            Continue {learnerName ? `${learnerName}’s` : 'the'} Shorter Catechism
          </Link>
          <div className="label-caps mt-3 text-[9px] tracking-[0.1em] text-ink-3">
            {localProgressLabel} · Q. {Math.min(localTrack!.currentQuestion, PROGRAM.totalQuestions)} next
          </div>
          <div className="mt-4 text-[13px] italic text-ink-2">
            Want progress on every device?{' '}
            <Link href={`/programs/${PROGRAM.slug}/save`} className="dotted-link text-ink">
              Save {learnerName ? `${learnerName}’s` : 'this'} progress
            </Link>
          </div>
        </div>
        <SupportingSections reflections={reflections} />
      </div>
    );
  }

  // Signed in but no children yet: add the child first (5b).
  if (children.length === 0) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Who Are You Catechizing?</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          Add a child to begin — just a name and an age.
        </p>
        <Link href="/onboarding/child" className="action-button mx-auto mt-6 max-w-72">
          Add a Child
        </Link>
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

        <div className="label-caps mb-3.5 text-center text-[9.5px] tracking-[0.12em] text-ink-3">
          {activeChild ? `${activeChild.name}’s Catechism` : 'Your Catechisms'}
        </div>

        {activeChild && assignment ? (
          <Link
            href={`/programs/${PROGRAM.slug}/session`}
            className="mb-[22px] block rounded-[2px] bg-fill px-5 pt-5 pb-[18px] text-inherit no-underline"
          >
            <div className="mb-1.5 font-display text-[14.5px] font-semibold text-ink">
              {PROGRAM.title}
            </div>
            <div className="mb-1.5 flex items-baseline justify-between">
              <span className="label-caps-sm text-[9px] text-ink-3">
                Q. {Math.min(assignment.current_question - 1, PROGRAM.totalQuestions)} of {PROGRAM.totalQuestions}
              </span>
            </div>
            <ProgressBar fraction={(assignment.current_question - 1) / PROGRAM.totalQuestions} />
          </Link>
        ) : activeChild && (
          <Link
            href={`/programs/${PROGRAM.slug}/start`}
            className="mb-[22px] block rounded-[2px] bg-fill px-5 pt-5 pb-[18px] text-inherit no-underline"
          >
            <div className="mb-1.5 font-display text-[14.5px] font-semibold text-ink">
              Start the Shorter Catechism for {activeChild.name}
            </div>
            <div className="text-[13px] italic text-ink-2">
              The Shorter Catechism — each question with its scripture and a prayer.
            </div>
          </Link>
        )}

        {otherPrograms.length > 0 && (
          <>
            <div className="mb-2.5 flex items-baseline justify-between">
              <div className="label-caps text-[10px] tracking-[0.14em] text-ink-3">
                Explore Other Catechisms
              </div>
            </div>
            <div className="flex flex-wrap gap-2.5">
              {otherPrograms.map((program) => (
                <Link
                  key={program.slug}
                  href={`/programs/${program.slug}`}
                  className="flex-1 min-w-[45%] rounded-[2px] bg-fill px-3.5 py-3.5 text-inherit no-underline"
                >
                  <div className="mb-1 font-display text-xs font-semibold text-ink">{program.title}</div>
                  <div className="text-[11px] text-ink-3">{program.totalQuestions} Q&A</div>
                </Link>
              ))}
            </div>
          </>
        )}
      </div>

      <SupportingSections reflections={reflections} showCatechisms={false} />
    </div>
  );
}
