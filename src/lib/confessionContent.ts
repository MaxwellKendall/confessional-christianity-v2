import type { ConfessionContent, ConfessionDocumentJson, ContentById } from './domain';

import wcf from '../../normalized-data/westminster/wcf.json';
import wlc from '../../normalized-data/westminster/wlc.json';
import wsc from '../../normalized-data/westminster/wsc.json';
import heidelbergCatechism from '../../normalized-data/three-forms-of-unity/heidelberg-catechism.json';
import canonsOfDort from '../../normalized-data/three-forms-of-unity/canons-of-dort.json';
import belgicConfession from '../../normalized-data/three-forms-of-unity/belgic-confession.json';
import thirtyNineArticles from '../../normalized-data/anglican/39-articles.json';
import ninetyFiveTheses from '../../normalized-data/reformation/95-theses.json';

// Statically imported so the bundler traces the data directly into every
// function that needs it. Reading these files from disk at runtime (via fs)
// breaks in Vercel's serverless bundles because the dynamic read path isn't
// traced, which caused v1's sitemap.xml to 500 with ENOENT in production.
// Keys must match slugByDocumentId in dataMapping.
const confessionDataByName: Record<string, ConfessionDocumentJson> = {
  'westminster-confession-of-faith': wcf as unknown as ConfessionDocumentJson,
  'westminster-larger-catechism': wlc as unknown as ConfessionDocumentJson,
  'westminster-shorter-catechism': wsc as unknown as ConfessionDocumentJson,
  'heidelberg-catechism': heidelbergCatechism as unknown as ConfessionDocumentJson,
  'canons-of-dort': canonsOfDort as unknown as ConfessionDocumentJson,
  'the-belgic-confession-of-faith': belgicConfession as unknown as ConfessionDocumentJson,
  'thirty-nine-articles-of-religion': thirtyNineArticles as unknown as ConfessionDocumentJson,
  'martin-luthers-95-theses': ninetyFiveTheses as unknown as ConfessionDocumentJson,
};

export const confessionSlugs = Object.keys(confessionDataByName);

// Loads a single confession/catechism's content keyed by id.
export const loadConfessionContent = async (slug: string): Promise<ConfessionContent | null> => {
  const parsed = confessionDataByName[slug];
  if (!parsed) return null;

  const contentById = parsed.content.reduce<ContentById>((asObj, obj) => ({
    ...asObj,
    [obj.id]: obj,
  }), {});

  // the canonical document id (e.g. WSC, WCoF) is derived from any entry
  // whose parent is the document itself (parent has no dash).
  const documentId = Object
    .entries(contentById)
    .find(([, v]) => v.parent.split('-').length === 1)![1].parent;

  return { contentById, documentId };
};
