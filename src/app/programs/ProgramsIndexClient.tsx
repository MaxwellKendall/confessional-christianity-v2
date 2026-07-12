'use client';

// /programs (mockup 2a): a plain catechism list, each row showing what
// it is, who it's for, and — if in progress — a one-line status.
import Link from 'next/link';

import { useChildren } from '@/hooks/useChildren';
import { PROGRAMS } from '@/lib/programs';

export function ProgramsIndexClient() {
  const { children } = useChildren();

  return (
    <div className="pb-6">
      <div className="px-5 pt-6 text-center">
        <h1 className="mb-2 font-display text-xl font-semibold">Catechisms</h1>
        <p className="px-2 text-[13px] italic leading-relaxed text-ink-2">
          Read, memorize, and teach historic catechisms with Scripture,
          prayer, and saved progress.
        </p>
      </div>

      <div className="mt-6 flex flex-col px-5">
        {PROGRAMS.map((program) => {
          const runs = children
            .map((child) => ({
              child,
              assignment: child.catechism_assignments
                ?.find((a) => a.catechism_id === program.catechismId) ?? null,
            }))
            .filter((r) => r.assignment);
          return (
            <Link
              key={program.slug}
              href={`/programs/${program.slug}`}
              className="border-t border-hairline py-4 text-ink no-underline last:border-b"
            >
              <div className="label-caps mb-1.5 text-[9px] tracking-[0.1em] text-ink-3">
                {program.kind}
              </div>
              <div className="mb-1 font-display text-[15px] font-semibold">{program.title}</div>
              <div className="mb-2 text-xs leading-relaxed text-ink-2">{program.description}</div>
              {runs.map(({ child, assignment }) => (
                <div key={child.id} className="label-caps text-[9.5px] tracking-[0.1em] text-ochre">
                  {assignment!.completed_at
                    ? `Complete · ${child.name}`
                    : `In progress · tracking for ${child.name} · Q. ${Math.min(assignment!.current_question - 1, program.totalQuestions)} of ${program.totalQuestions}`}
                </div>
              ))}
            </Link>
          );
        })}
      </div>
    </div>
  );
}
