'use client';

// "Jump to Question" (mockup 8d): a searchable index of every question in the
// catechism, reached by tapping the "Question N of Total" label on the
// session screen (8a/8b/8c). Browsing here is the same "look, don't lose your
// place" move as the review step — picking a question repositions the local
// track (jumpToLocalQuestion), it doesn't re-introduce material.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useMemo, useState } from 'react';

import { getLocalCatechismTrack, jumpToLocalQuestion } from '@/lib/localCatechismProgress';
import { listQuestions } from '@/lib/programContent';
import { getProgram } from '@/lib/programs';
import { SearchIcon } from '@/components/SearchIcon';

const PAGE_SIZE = 10;

export function JumpToQuestionClient({ slug }: { slug: string }) {
  const program = getProgram(slug)!;
  const router = useRouter();
  const questions = useMemo(() => listQuestions(program), [program]);
  const currentQuestion = useMemo(
    () => getLocalCatechismTrack(program.contentId)?.currentQuestion ?? null,
    [program.contentId],
  );

  const [query, setQuery] = useState('');
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return questions;
    return questions.filter((item) => (
      String(item.number) === q || item.question.toLowerCase().includes(q)
    ));
  }, [questions, query]);

  const visible = filtered.slice(0, visibleCount);
  const remaining = filtered.length - visible.length;

  const goTo = (n: number) => {
    jumpToLocalQuestion(program.contentId, n, program.totalQuestions);
    router.push(`/programs/${slug}/session`);
  };

  return (
    <div className="min-h-[calc(100dvh-4rem)] pb-10">
      <div className="flex items-center px-5 pt-5 pb-4">
        <Link
          href={`/programs/${slug}/session`}
          aria-label="Back to session"
          className="font-display text-[15px] text-ink no-underline"
        >
          ←
        </Link>
        <div className="label-caps flex-1 text-center text-[10px] tracking-[0.14em] text-ink-3">
          Jump to Question
        </div>
        <span className="w-[15px]" aria-hidden="true" />
      </div>

      <div className="px-5">
        <div className="flex items-center gap-2.5 rounded-full bg-fill px-4 py-3">
          <span className="shrink-0 text-ink-3">
            <SearchIcon />
          </span>
          <input
            type="text"
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setVisibleCount(PAGE_SIZE);
            }}
            placeholder="Search by number or phrase…"
            aria-label="Search by number or phrase"
            className="w-full min-w-0 border-none bg-transparent font-body text-[13.5px] italic text-ink outline-none placeholder:text-ink-3"
          />
        </div>
      </div>

      <div className="label-caps mt-5 px-5 text-[9.5px] tracking-[0.1em] text-ink-3">
        {query
          ? `${filtered.length} Match${filtered.length === 1 ? '' : 'es'}`
          : `Questions 1–${visible.length}`}
      </div>

      {visible.length === 0 ? (
        <p className="px-5 pt-6 text-center text-[13px] italic text-ink-2">
          No questions match &ldquo;{query}&rdquo;.
        </p>
      ) : (
        <div className="mt-2">
          {visible.map((item) => {
            const active = item.number === currentQuestion;
            return (
              <button
                key={item.number}
                type="button"
                onClick={() => goTo(item.number)}
                className={`flex w-full cursor-pointer items-baseline gap-4 border-none px-5 py-3.5 text-left ${active ? 'bg-ochre/10' : 'bg-transparent'}`}
              >
                <span className={`w-5 shrink-0 font-display text-sm ${active ? 'text-ochre' : 'text-ink-3'}`}>
                  {item.number}
                </span>
                <span className="font-body text-[15px] italic text-ink">{item.question}</span>
              </button>
            );
          })}
        </div>
      )}

      {remaining > 0 && (
        <button
          type="button"
          onClick={() => setVisibleCount((c) => c + PAGE_SIZE)}
          className="label-caps mx-auto mt-2 block cursor-pointer border-none bg-transparent pt-4 text-[9.5px] tracking-[0.1em] text-muted"
        >
          {remaining} more question{remaining === 1 ? '' : 's'} below…
        </button>
      )}
    </div>
  );
}
