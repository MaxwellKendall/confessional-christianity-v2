import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';

import { confessionSlugs } from '@/lib/confessionContent';
import { documentIdBySlug } from '@/lib/dataMapping';
import { entryIdToPathSegment, truncateForMeta } from '@/lib/helpers';
import { tocRowTitle } from '@/lib/entryDisplay';
import {
  getDocumentDescription,
  getLibraryDocument,
  getOrderedEntries,
} from '@/lib/library';
import { listCommentaryIds } from '@/lib/commentary';

interface Params {
  confession: string;
}

export const dynamicParams = false;

export async function generateStaticParams(): Promise<Params[]> {
  return confessionSlugs.map((confession) => ({ confession }));
}

export async function generateMetadata(
  { params }: { params: Promise<Params> },
): Promise<Metadata> {
  const { confession } = await params;
  const doc = getLibraryDocument(confession);
  if (!doc) return {};
  return {
    title: doc.name,
    description: truncateForMeta(await getDocumentDescription(confession)),
    alternates: { canonical: `/library/${confession}` },
  };
}

export default async function ConfessionTocPage(
  { params }: { params: Promise<Params> },
) {
  const { confession } = await params;
  const doc = getLibraryDocument(confession);
  if (!doc) notFound();

  const documentId = documentIdBySlug[confession];
  const [entries, commentaryIds] = await Promise.all([
    getOrderedEntries(confession),
    listCommentaryIds(),
  ]);
  const hasCommentary = new Set(commentaryIds);

  return (
    <div className="pb-6">
      <div className="px-5 pt-5">
        <Link href="/library" className="label-caps dotted-link text-[9.5px] tracking-[0.1em] text-ink-3">
          Library
        </Link>
      </div>
      <div className="px-5 pt-2.5 text-center">
        <h1 className="mb-2 heading-page">{doc.name}</h1>
        <p className="text-[12.5px] italic text-ink-2">{doc.blurb}</p>
      </div>

      <div className="mt-5 flex flex-col px-5">
        {entries.map((entry, i) => (entry.isParent ? (
          <div
            key={entry.id}
            className={`border-t border-hairline pt-4 pb-1.5 label-caps text-[9.5px] tracking-[0.1em] text-ink-3 ${i === 0 ? '' : 'mt-2'}`}
          >
            {entry.title}
          </div>
        ) : (
          <Link
            key={entry.id}
            href={`/library/${confession}/${entryIdToPathSegment(entry.id, documentId)}`}
            className="border-t border-hairline py-[11px] text-ink no-underline last:border-b"
          >
            <span className="font-display text-[13.5px] font-semibold">
              {hasCommentary.has(entry.id) && <span aria-hidden="true">† </span>}
              {tocRowTitle(entry)}
            </span>
          </Link>
        )))}
      </div>
    </div>
  );
}
