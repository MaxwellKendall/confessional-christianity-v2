'use client';

// Catechism-first start: users choose what to study and where to begin before
// account creation. Authenticated households can attach that progress to a
// child; anonymous users get local, same-device progress.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { useAuth } from '@/context/AuthContext';
import { useChildren } from '@/hooks/useChildren';
import { useProgramState } from '@/hooks/useProgramState';
import { setActiveChildId } from '@/lib/activeChild';
import { startLocalCatechismTrack } from '@/lib/localCatechismProgress';
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
  const [startingQuestion, setStartingQuestion] = useState(1);

  const validateStartingQuestion = () => {
    if (!Number.isInteger(startingQuestion)) return 'Choose a whole question number.';
    if (startingQuestion < 1 || startingQuestion > program.totalQuestions) {
      return `Choose a question between 1 and ${program.totalQuestions}.`;
    }
    return null;
  };

  const beginLocally = () => {
    const validation = validateStartingQuestion();
    if (validation) {
      setError(validation);
      return;
    }
    startLocalCatechismTrack(program.contentId, startingQuestion);
    router.push(`/programs/${slug}/session`);
  };

  const onChoose = async (child: ChildWithRole) => {
    setError(null);
    const validation = validateStartingQuestion();
    if (validation) {
      setError(validation);
      return;
    }
    setStartingId(child.id);
    try {
      const existing = child.catechism_assignments
        ?.some((a) => a.catechism_id === program.contentId);
      if (!existing) await startProgram(child, startingQuestion);
      setActiveChildId(child.id);
      router.push(`/programs/${slug}/session`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start the catechism');
      setStartingId(null);
    }
  };

  return (
    <div className="pb-6">
      <div className="border-b border-hairline px-5 pt-4 pb-3 text-center label-caps text-[9.5px] tracking-[0.1em]">
        <Link href={`/programs/${slug}`} className="dotted-link text-ink-3">
          {program.title}
        </Link>
      </div>

      <div className="px-8 pt-9 text-center">
        <div className="label-caps mb-3 text-[9.5px] text-ink-3">Begin</div>
        <h1 className="mb-2 font-display text-lg font-semibold">Start {program.title}</h1>
        <p className="mx-auto mb-7 max-w-[24rem] text-[12.5px] italic leading-relaxed text-ink-2">
          Begin with Question 1, or jump to the question your family is already
          learning. Progress can be saved on this device before you create an
          account.
        </p>
      </div>

      {error && (
        <p className="mb-4 px-8 text-center text-[12.5px] italic text-ink-2" role="alert">{error}</p>
      )}

      <div className="mx-5 border-y border-hairline py-4">
        <label className="label-caps mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3" htmlFor="catechism">
          Catechism
        </label>
        <select
          id="catechism"
          value={program.contentId}
          disabled
          className="w-full rounded-[2px] border border-hairline bg-card px-3 py-3 font-display text-[14px] text-ink"
        >
          <option value={program.contentId}>{program.title}</option>
        </select>

        <label className="label-caps mt-5 mb-2 block text-[9.5px] tracking-[0.1em] text-ink-3" htmlFor="starting-question">
          Starting Question
        </label>
        <input
          id="starting-question"
          type="number"
          min={1}
          max={program.totalQuestions}
          value={startingQuestion}
          onChange={(event) => setStartingQuestion(Number(event.target.value))}
          className="w-full rounded-[2px] border border-hairline bg-card px-3 py-3 font-display text-[14px] text-ink"
        />
      </div>

      {!authLoading && !user && (
        <div className="mx-5 mt-5 text-center">
          <button type="button" onClick={beginLocally} className="action-button w-full cursor-pointer">
            Begin Without an Account
          </button>
          <p className="mx-auto mt-3 max-w-[24rem] text-[12px] italic leading-relaxed text-ink-2">
            Progress will be saved on this device. Create an account later to
            keep it safe, sync it, or add another child.
          </p>
        </div>
      )}

      {user && (
        <div className="mt-6">
          <div className="px-8 text-center">
            <h2 className="mb-2 font-display text-[15px] font-semibold">Save Progress For</h2>
            <p className="mb-4 text-[12.5px] italic text-ink-2">
              Choose a child, or add one if this is your first saved catechism.
            </p>
          </div>

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
      )}
    </div>
  );
}
