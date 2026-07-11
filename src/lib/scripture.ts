// Read-side accessors for /scripture/[osis], the canonical page for a proof
// text: every confession clause that cites a given scripture reference.
// Build-time only — the map inverts the same normalized-data `verses` records
// the citations index was built from, so every indexed citation has a page.
import { clauseForMarker, entryPageLabel } from './entryDisplay';
import { entryIdToPathSegment } from './helpers';
import { LIBRARY_DOCUMENTS, getOrderedLeafEntries } from './library';
import { loadConfessionContent } from './confessionContent';

export interface ScriptureCitingEntry {
  entryId: string;
  documentTitle: string;
  entryLabel: string;
  href: string;
  clause: string;
}

let indexPromise: Promise<Map<string, ScriptureCitingEntry[]>> | null = null;

const buildIndex = async (): Promise<Map<string, ScriptureCitingEntry[]>> => {
  const index = new Map<string, ScriptureCitingEntry[]>();
  for (const doc of LIBRARY_DOCUMENTS) {
    const content = await loadConfessionContent(doc.slug);
    if (!content) continue;
    const leaves = await getOrderedLeafEntries(doc.slug);
    for (const entry of leaves) {
      for (const [marker, refs] of Object.entries(entry.verses ?? {})) {
        for (const osis of refs) {
          const citing = index.get(osis) ?? [];
          citing.push({
            entryId: entry.id,
            documentTitle: doc.name,
            entryLabel: entryPageLabel(entry, content.contentById),
            href: `/library/${doc.slug}/${entryIdToPathSegment(entry.id, content.documentId)}`,
            clause: clauseForMarker(entry, marker),
          });
          index.set(osis, citing);
        }
      }
    }
  }
  return index;
};

const getIndex = (): Promise<Map<string, ScriptureCitingEntry[]>> => {
  indexPromise ??= buildIndex();
  return indexPromise;
};

// route enumeration for generateStaticParams on /scripture/[osis].
export const getAllScriptureParams = async (): Promise<{ osis: string }[]> => {
  const index = await getIndex();
  return Array.from(index.keys()).map((osis) => ({ osis }));
};

// every confession clause citing the reference, in library document order.
export const getScriptureCitingEntries = async (osis: string): Promise<ScriptureCitingEntry[]> => {
  const index = await getIndex();
  return index.get(osis) ?? [];
};
