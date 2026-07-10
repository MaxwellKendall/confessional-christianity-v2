// Read-side accessors for the /library surface. Everything here is pure and
// build-time only: the loaders statically import the confession JSON, so
// library pages render as fully static RSC with no runtime data source.
import { confessionSlugs, loadConfessionContent } from './confessionContent';
import { documentIdBySlug } from './dataMapping';
import { compareEntryIds, entryIdToPathSegment, stripFootnoteMarkers } from './helpers';
import type { ConfessionEntry } from './domain';

// Editorial metadata for the library index and document pages. The blurbs are
// the design handoff's copy (mockup 1f), which is final, not placeholder.
export interface LibraryDocument {
  slug: string;
  documentId: string;
  name: string;
  blurb: string;
}

export const LIBRARY_DOCUMENTS: LibraryDocument[] = [
  {
    slug: 'westminster-shorter-catechism',
    documentId: 'WSC',
    name: 'Westminster Shorter Catechism',
    blurb: 'A 1647 primer in question-and-answer form, still used to teach the faith.',
  },
  {
    slug: 'westminster-confession-of-faith',
    documentId: 'WCoF',
    name: 'Westminster Confession of Faith',
    blurb: 'The 1646 confession underlying Presbyterian doctrine.',
  },
  {
    slug: 'westminster-larger-catechism',
    documentId: 'WLC',
    name: 'Westminster Larger Catechism',
    blurb: 'The 1647 companion catechism, fuller in both doctrine and duty.',
  },
  {
    slug: 'heidelberg-catechism',
    documentId: 'HC',
    name: 'Heidelberg Catechism',
    blurb: 'A 1563 catechism prized for its pastoral warmth.',
  },
  {
    slug: 'the-belgic-confession-of-faith',
    documentId: 'TBCoF',
    name: 'Belgic Confession',
    blurb: 'A 1561 statement of Reformed belief, Dutch tradition.',
  },
  {
    slug: 'canons-of-dort',
    documentId: 'CoD',
    name: 'Canons of Dort',
    blurb: 'The 1619 Synod’s judgment on grace and election.',
  },
  {
    slug: 'thirty-nine-articles-of-religion',
    documentId: 'TAoR',
    name: 'Thirty-Nine Articles',
    blurb: 'The doctrinal basis of the Church of England, settled 1571.',
  },
  {
    slug: 'martin-luthers-95-theses',
    documentId: 'ML9t',
    name: 'Luther’s Ninety-Five Theses',
    blurb: 'The 1517 propositions that opened the Reformation.',
  },
];

export const getLibraryDocument = (slug: string): LibraryDocument | null => LIBRARY_DOCUMENTS
  .find((d) => d.slug === slug) ?? null;

export interface AdjacentEntry {
  href: string;
  title: string;
}

export interface EntryPage {
  item: ConfessionEntry;
  documentId: string;
  documentTitle: string;
  slug: string;
  prevEntry: AdjacentEntry | null;
  nextEntry: AdjacentEntry | null;
}

// leaf entries of a document, in canonical document order.
export const getOrderedLeafEntries = async (slug: string): Promise<ConfessionEntry[]> => {
  const content = await loadConfessionContent(slug);
  if (!content) return [];
  return Object.values(content.contentById)
    .filter((entry) => !entry.isParent)
    .sort((a, b) => compareEntryIds(a.id, b.id));
};

// every entry (parents included), in canonical document order — for TOCs.
export const getOrderedEntries = async (slug: string): Promise<ConfessionEntry[]> => {
  const content = await loadConfessionContent(slug);
  if (!content) return [];
  return Object.values(content.contentById).sort((a, b) => compareEntryIds(a.id, b.id));
};

// short leaf title for prev/next links: "Article 3", "Q. 4", "Thesis 12".
const shortEntryTitle = (entry: ConfessionEntry): string => {
  const title = entry.title || '';
  const colonIndex = title.indexOf(':');
  const head = colonIndex > 0 ? title.slice(0, colonIndex) : title;
  return head.replace(/^Question\b/, 'Q.');
};

// Resolves the [entry] path segment (dash-joined, e.g. "1-2" or
// "1-articles-3") for a document slug to the entry plus its adjacent leaf
// entries. Returns null for unknown documents, parent ids, or malformed
// segments — the route turns that into notFound().
export const getEntryPage = async (slug: string, segment: string): Promise<EntryPage | null> => {
  const doc = getLibraryDocument(slug);
  const content = await loadConfessionContent(slug);
  if (!doc || !content) return null;

  const entryId = `${content.documentId}-${segment}`;
  const item = content.contentById[entryId];
  if (!item || item.isParent) return null;

  const leaves = await getOrderedLeafEntries(slug);
  const index = leaves.findIndex((e) => e.id === entryId);
  const toAdjacent = (adjacent: ConfessionEntry | undefined): AdjacentEntry | null => (
    adjacent
      ? {
        href: `/library/${slug}/${entryIdToPathSegment(adjacent.id, content.documentId)}`,
        title: shortEntryTitle(adjacent),
      }
      : null
  );

  return {
    item,
    documentId: content.documentId,
    documentTitle: doc.name,
    slug,
    prevEntry: toAdjacent(leaves[index - 1]),
    nextEntry: toAdjacent(leaves[index + 1]),
  };
};

// route enumeration for generateStaticParams on /library/[confession]/[entry].
export const getAllEntryParams = async (): Promise<{ confession: string; entry: string }[]> => {
  const params: { confession: string; entry: string }[] = [];
  for (const slug of confessionSlugs) {
    const documentId = documentIdBySlug[slug];
    const leaves = await getOrderedLeafEntries(slug);
    for (const leaf of leaves) {
      params.push({ confession: slug, entry: entryIdToPathSegment(leaf.id, documentId) });
    }
  }
  return params;
};

// meta description for a document page: the opening of its first leaf entry.
export const getDocumentDescription = async (slug: string): Promise<string> => {
  const leaves = await getOrderedLeafEntries(slug);
  const first = leaves[0];
  if (!first?.text) return getLibraryDocument(slug)?.blurb ?? '';
  return stripFootnoteMarkers(first.text);
};
