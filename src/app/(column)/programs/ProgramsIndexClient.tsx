'use client';

// /programs (mockup 2a): a plain catechism list, each row showing what
// it is and who it's for.
import Link from 'next/link';

import { PROGRAMS } from '@/lib/programs';

export function ProgramsIndexClient() {
  return (
    <div className="pb-6">
      <div className="px-5 pt-6 text-center">
        <h1 className="mb-2 heading-page">Catechisms</h1>
        <p className="px-2 text-[13px] italic leading-relaxed text-ink-2">
          Read, memorize, and teach historic catechisms with Scripture,
          prayer, and saved progress.
        </p>
      </div>

      <div className="mt-6 flex flex-col px-5">
        {PROGRAMS.map((program) => (
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
          </Link>
        ))}
      </div>
    </div>
  );
}
