// Series parts for a catechism-sourced run, one per top-level entry in
// document order, so an author starting the WLC run begins from 196 named
// parts instead of typing them. Server-only: reads the ~700K content map.
import contentByIdJson from '../../../dataMapping/content-by-id.json';
import { getDocumentById } from '../catechisms';
import { parentIdByAbbreviation } from '../dataMapping';
import type { SeriesPart } from '../devotionSeries';

interface ContentEntry {
  id: string;
  title?: string;
  parent?: string;
  number?: number;
}

const contentById = contentByIdJson as unknown as Record<string, ContentEntry>;

export const catechismSeriesParts = (documentId: string): SeriesPart[] => {
  const doc = getDocumentById(documentId);
  if (!doc) return [];
  const parent = parentIdByAbbreviation[documentId.toUpperCase()] ?? documentId;
  return Object.values(contentById)
    .filter((entry) => entry.parent === parent && typeof entry.number === 'number')
    .sort((a, b) => (a.number ?? 0) - (b.number ?? 0))
    .map((entry, i) => {
      const n = entry.number ?? i + 1;
      const title = entry.title ?? '';
      const question = title.match(/^Question \d+:\s*(.+)$/);
      if (question) return { day: i + 1, title: question[1], citation: `${doc.shortName} Q. ${n}` };
      // grouped documents (the Heidelberg's Lord's Days) name the group
      if (/\d+$/.test(title)) return { day: i + 1, title, citation: `${doc.shortName} ${title}` };
      return { day: i + 1, title, citation: `${doc.shortName} ${doc.itemLabel} ${n}` };
    });
};
