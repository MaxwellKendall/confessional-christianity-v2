'use client';

// Add a child (mockup 5b, PRD §12): a name and an age — age sets pacing
// defaults, nothing more. Reachable from onboarding, the homepage +, and the
// start-a-program flow.
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { setActiveChildId } from '@/lib/activeChild';

export function AddChildClient() {
  const { user, loading: authLoading } = useAuth();
  const { addChild } = useChildren();
  const router = useRouter();
  const searchParams = useSearchParams();
  const returnTo = searchParams.get('then') ?? '/';

  const [name, setName] = useState('');
  const [age, setAge] = useState(7);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!authLoading && !user) {
    return (
      <div className="px-9 pt-14 text-center">
        <h1 className="mb-2.5 font-display text-[19px] font-semibold">Who Are You Catechizing?</h1>
        <p className="text-[13px] italic leading-relaxed text-ink-2">
          <Link href="/auth/signup" className="dotted-link text-ink">Create an account</Link>
          {' '}or{' '}
          <Link href="/auth/signin" className="dotted-link text-ink">sign in</Link>
          {' '}first — a child’s plan needs somewhere to live.
        </p>
      </div>
    );
  }

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setError('A name is all we need.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const updated = await addChild(name.trim(), age);
      // rows come back in created_at order, so the new child is last
      const newest = updated[updated.length - 1];
      if (newest) setActiveChildId(newest.id);
      router.push(returnTo);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not add child');
      setSubmitting(false);
    }
  };

  return (
    <div className="px-9 pt-14 pb-10 text-center">
      <h1 className="mb-2.5 font-display text-[19px] font-semibold">Who Are You Catechizing?</h1>
      <p className="mb-10 text-[13px] italic leading-relaxed text-ink-2">
        Just a name and an age — age sets a sensible starting pace, nothing more.
      </p>

      <form onSubmit={onSubmit} className="text-left">
        <div className="mb-7">
          <label htmlFor="child-name" className="label-caps mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3">
            Name
          </label>
          <input
            id="child-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full border-b border-ink bg-transparent pb-2 font-body text-[17px] italic text-ink outline-none"
          />
        </div>

        <div className="mb-11">
          <div className="label-caps mb-2 text-[9.5px] tracking-[0.1em] text-ink-3">Age</div>
          <div className="flex items-center justify-between border-b border-ink pb-2">
            <span className="font-body text-[17px] italic text-ink">{age}</span>
            <div className="flex gap-4 font-display text-[13px] text-ink">
              <button
                type="button"
                aria-label="Decrease age"
                onClick={() => setAge((a) => Math.max(2, a - 1))}
                className="cursor-pointer border-none bg-transparent font-display text-[13px] text-ink"
              >
                −
              </button>
              <button
                type="button"
                aria-label="Increase age"
                onClick={() => setAge((a) => Math.min(18, a + 1))}
                className="cursor-pointer border-none bg-transparent font-display text-[13px] text-ink"
              >
                +
              </button>
            </div>
          </div>
        </div>

        {error && (
          <p className="mb-5 text-center text-[12.5px] italic text-ink-2" role="alert">{error}</p>
        )}

        <button type="submit" disabled={submitting} className="action-button w-full cursor-pointer bg-transparent">
          {submitting ? 'One moment…' : name.trim() ? `Add ${name.trim()}` : 'Add a Child'}
        </button>
      </form>
    </div>
  );
}
