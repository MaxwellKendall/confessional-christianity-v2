import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { EsvPassage } from '@/components/EsvPassage';
import { parseOsisBibleReference } from '@/lib/bible';
import { getAllScriptureParams, getScriptureCitingEntries } from '@/lib/scripture';

interface Params {
  osis: string;
}

export const dynamicParams = false;

export async function generateStaticParams(): Promise<Params[]> {
  return getAllScriptureParams();
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { osis } = await params;
  const citing = await getScriptureCitingEntries(osis);
  if (!citing.length) return {};
  const citation = parseOsisBibleReference(osis);
  const documents = Array.from(new Set(citing.map((c) => c.documentTitle)));
  return {
    title: citation,
    description: `${citation} as cited by ${documents.join(', ')} — every clause of the confessions resting on this text.`,
    alternates: { canonical: `/scripture/${osis}` },
  };
}

// The clause can open far from its marker in long prose entries; keep the
// tail, which is what the citation actually anchors to.
const trimClause = (clause: string): string => (
  clause.length > 220 ? `…${clause.slice(-220).trimStart()}` : clause
);

export default async function ScripturePage({ params }: { params: Promise<Params> }) {
  const { osis } = await params;
  const citing = await getScriptureCitingEntries(osis);
  if (!citing.length) notFound();

  const citation = parseOsisBibleReference(osis);
  const byDocument = citing.reduce<{ documentTitle: string; entries: typeof citing }[]>(
    (acc, entry) => {
      const group = acc.find((g) => g.documentTitle === entry.documentTitle);
      if (group) group.entries.push(entry);
      else acc.push({ documentTitle: entry.documentTitle, entries: [entry] });
      return acc;
    },
    [],
  );

  return (
    <div className="pb-6">
      <div className="px-5 pt-5 label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
        Scripture
      </div>

      <div className="px-11 pt-5 text-center">
        <h1 className="mb-4 heading-page">{citation}</h1>
        <EsvPassage osis={osis} />
      </div>

      <div className="mx-5 mt-7 border-t border-hairline pt-4">
        <div className="label-caps mb-3 text-[9.5px] text-ink-3">Cited in the Confessions</div>
        <div className="flex flex-col gap-4">
          {byDocument.map((group) => (
            <div key={group.documentTitle}>
              <div className="label-caps mb-1.5 text-[9px] tracking-[0.1em] text-ink-3">
                {group.documentTitle}
              </div>
              <div className="flex flex-col gap-2.5">
                {group.entries.map((entry, i) => (
                  <div key={`${entry.entryId}-${i}`} className="text-[13px] leading-relaxed">
                    <Link href={entry.href} className="dotted-link font-display text-ink">
                      {entry.entryLabel}
                    </Link>
                    {entry.clause && (
                      <span className="text-ink-2">
                        {' — '}
                        <q className="italic">{trimClause(entry.clause)}</q>
                      </span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
