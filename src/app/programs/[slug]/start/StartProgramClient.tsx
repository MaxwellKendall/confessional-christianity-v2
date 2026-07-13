'use client';

// Catechism-first start: choose what to study and where to begin. Progress
// is local to this device, no account.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';

import { startLocalCatechismTrack } from '@/lib/localCatechismProgress';
import { getProgram } from '@/lib/programs';

export function StartProgramClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
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
          learning. Progress is saved on this device.
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

      <div className="mx-5 mt-5 text-center">
        <button type="button" onClick={beginLocally} className="action-button w-full cursor-pointer">
          Begin the Catechism
        </button>
        <p className="mx-auto mt-3 max-w-[24rem] text-[12px] italic leading-relaxed text-ink-2">
          Progress will be saved on this device.
        </p>
      </div>
    </div>
  );
}
