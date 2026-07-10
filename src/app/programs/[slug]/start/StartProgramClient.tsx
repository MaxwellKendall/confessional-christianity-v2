'use client';

// Choose a child to start a program (mockup 5c, PRD §5.5): every plan belongs
// to one child; choosing (or adding) one is part of starting, never a buried
// setting.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { setActiveChildId } from '@/lib/activeChild';
import { getProgram } from '@/lib/programs';
import type { ChildWithRole } from '@/lib/database.types';

export function StartProgramClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const { user, loading: authLoading } = useAuth();
  const { children, loading: childrenLoading } = useChildren();
  const { startProgram } = useProgramState(program, null);
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [startingId, setStartingId] = useState<string | null>(null);

  const onChoose = async (child: ChildWithRole) => {
    setError(null);
    setStartingId(child.id);
    try {
      const existing = child.catechism_assignments
        ?.some((a) => a.catechism_id === program.catechismId);
      if (!existing) await startProgram(child);
      setActiveChildId(child.id);
      router.push(`/programs/${slug}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start the program');
      setStartingId(null);
    }
  };

  if (!authLoading && !user) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-lg font-semibold">Who Is This Plan For?</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          <Link href="/auth/signup" className="dotted-link text-ink">Create an account</Link>
          {' '}first — a plan belongs to one child, and both need somewhere to live.
        </p>
      </div>
    );
  }

  return (
    <div className="pb-6">
      <div className="border-b border-hairline px-5 pt-4 pb-3 text-center label-caps text-[9.5px] tracking-[0.1em]">
        <Link href={`/programs/${slug}`} className="dotted-link text-ink-3">
          Catechizing Your Child
        </Link>
      </div>

      <div className="px-8 pt-9 text-center">
        <h1 className="mb-2 font-display text-lg font-semibold">Who Is This Plan For?</h1>
        <p className="mb-8 text-[12.5px] italic text-ink-2">
          Every plan belongs to one child. Choose who’s starting the Shorter
          Catechism.
        </p>
      </div>

      {error && (
        <p className="mb-4 px-8 text-center text-[12.5px] italic text-ink-2" role="alert">{error}</p>
      )}

      <div className="flex flex-col px-5">
        {children.map((child) => (
          <button
            key={child.id}
            type="button"
            disabled={childrenLoading || startingId !== null}
            onClick={() => onChoose(child)}
            className="flex cursor-pointer items-baseline justify-between border-x-0 border-b-0 border-t border-solid border-hairline bg-transparent px-1 py-4 text-left"
          >
            <span className="font-display text-[15px] font-semibold text-ink">
              {startingId === child.id ? `Starting for ${child.name}…` : child.name}
            </span>
            {child.age !== null && (
              <span className="label-caps-sm text-[9.5px] text-ink-3">Age {child.age}</span>
            )}
          </button>
        ))}
        <Link
          href={`/onboarding/child?then=/programs/${slug}/start`}
          className="border-y border-hairline px-1 pt-4 pb-5 text-[13.5px] italic text-ink-2 no-underline"
        >
          + Add a Child
        </Link>
      </div>
    </div>
  );
}
