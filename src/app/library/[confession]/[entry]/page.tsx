import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { parseOsisBibleReference } from '@/lib/bible';
import { entryPageLabel, entryQuoteLines, proofTextRefs } from '@/lib/entryDisplay';
import { truncateForMeta } from '@/lib/helpers';
import { getAllEntryParams, getEntryPage } from '@/lib/library';
import { loadConfessionContent } from '@/lib/confessionContent';
import { getReflectionByEntryId } from '@/lib/reflections';

interface Params {
  confession: string;
  entry: string;
}

export const dynamicParams = false;

export async function generateStaticParams(): Promise<Params[]> {
  return getAllEntryParams();
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { confession, entry } = await params;
  const page = await getEntryPage(confession, entry);
  if (!page) return {};
  const content = await loadConfessionContent(confession);
  const label = entryPageLabel(page.item, content?.contentById);
  return {
    title: `${page.documentTitle} — ${label}`,
    description: truncateForMeta(page.item.text ?? page.item.title),
    alternates: { canonical: `/library/${confession}/${entry}` },
  };
}

export default async function EntryPage({ params }: { params: Promise<Params> }) {
  const { confession, entry } = await params;
  const page = await getEntryPage(confession, entry);
  if (!page) notFound();

  const content = await loadConfessionContent(confession);
  const label = entryPageLabel(page.item, content?.contentById);
  const quoteLines = entryQuoteLines(page.item);
  const proofTexts = proofTextRefs(page.item).map(parseOsisBibleReference);
  const reflection = await getReflectionByEntryId(page.item.id);

  return (
    <div className="pb-6">
      <div className="px-5 pt-5 label-caps text-[9.5px] tracking-[0.1em] text-ink-3">
        <Link href="/library" className="dotted-link text-ink-3">Library</Link>
        {' / '}
        <Link href={`/library/${confession}`} className="text-ink-3 no-underline">
          {page.documentTitle}
        </Link>
      </div>

      <div className="px-11 pt-5 text-center">
        <div className="label-caps mb-4 text-[9.5px] text-ink-3">{label}</div>
        <blockquote className="m-0 font-body text-[17px] italic leading-[1.55] text-ink">
          {quoteLines.map((line, i) => (
            <span key={i}>
              {i > 0 && <br />}
              {line}
            </span>
          ))}
        </blockquote>
      </div>

      {reflection && (
        <div className="mx-5 mt-6 border-t border-hairline pt-4 text-center">
          <Link
            href={`/reflections/${reflection.slug}`}
            className="label-caps dotted-link text-[9.5px] text-ink"
          >
            <span aria-hidden="true">† </span>
            Commentary — {reflection.title}
          </Link>
        </div>
      )}

      {proofTexts.length > 0 && (
        <div className="mx-5 mt-6 border-t border-hairline pt-4">
          <div className="label-caps mb-2 text-[9.5px] text-ink-3">Proof Texts</div>
          <div className="text-[13px] leading-[1.9] text-ink-2">
            {proofTexts.join(' · ')}
          </div>
        </div>
      )}

      <div className="mx-5 mt-7 flex items-center justify-between border-t border-hairline pt-4 label-caps text-[10px] tracking-[0.1em]">
        {page.prevEntry ? (
          <Link href={page.prevEntry.href} className="dotted-link text-ink">
            ← {page.prevEntry.title}
          </Link>
        ) : (
          <span className="text-muted">← Prev</span>
        )}
        {page.nextEntry ? (
          <Link href={page.nextEntry.href} className="dotted-link text-ink">
            {page.nextEntry.title} →
          </Link>
        ) : (
          <span className="text-muted">Next →</span>
        )}
      </div>
    </div>
  );
}
