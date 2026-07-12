'use client';

// "Pray About This" as its own screen (mockup 8b) — one tap from the
// question, one tap back. A prayer written directly off the question and
// its Scripture, held on its own so it isn't squeezed into an in-place
// expansion under the answer.
import { useRouter, useSearchParams } from 'next/navigation';

import { getPrayer, getWscQuestion } from '@/lib/programContent';

export function PrayerClient({
  questionNumber, totalQuestions,
}: { questionNumber: number; totalQuestions: number }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const childName = searchParams.get('child') ?? 'your child';

  const question = getWscQuestion(questionNumber);
  const prayer = getPrayer(questionNumber, childName);

  const goBack = () => router.back();

  if (!question) return null;

  return (
    <div className="flex min-h-[calc(100dvh-7rem)] flex-col">
      <div className="flex items-center justify-between px-6 pt-5">
        <button
          type="button"
          aria-label="Back to the question"
          onClick={goBack}
          className="cursor-pointer border-none bg-transparent p-0 font-display text-[15px] text-ink"
        >
          ←
        </button>
        <div className="label-caps text-[9.5px] tracking-[0.12em] text-ochre">
          Question {questionNumber} of {totalQuestions}
        </div>
      </div>

      <div className="flex flex-1 flex-col items-center justify-center px-9 py-6 text-center">
        <div className="label-caps mb-2.5 text-[9px] tracking-[0.14em] text-ink-3">
          A Prayer on &ldquo;{question.question.replace(/\?$/, '')}&rdquo;
        </div>
        <div className="mb-6 h-px w-9 bg-hairline" aria-hidden="true" />
        {prayer ? (
          <>
            <p className="m-0 font-body text-[15.5px] italic leading-[1.85] text-ink">{prayer}</p>
            <div className="label-caps mt-5.5 text-[11px] tracking-[0.1em] text-ochre">Amen</div>
          </>
        ) : (
          <p className="m-0 text-[13px] italic text-heart-reviewing">
            The prayer for this question isn’t written yet — close in your own words.
          </p>
        )}
      </div>

      <div className="border-t border-hairline px-6 pt-4.5 pb-10 text-center">
        <button
          type="button"
          onClick={goBack}
          className="label-caps cursor-pointer border-none bg-transparent pb-0.5 text-[11px] tracking-[0.1em] text-ink"
          style={{ borderBottom: '1px dotted var(--color-ink)' }}
        >
          Back to the Question
        </button>
      </div>
    </div>
  );
}
