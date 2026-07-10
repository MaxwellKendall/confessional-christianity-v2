// Document-alias vocabularies, ported from v1 dataMapping/index.js.
// See docs/DOMAIN.md before touching anything keyed by these maps.

export const confessionCitationByIndex: Record<string, string[]> = {
  WCF: ['Westminster Confession of Faith', 'Chapter', 'Article', 'Scripture Citation'],
  WCoF: ['Westminster Confession of Faith', 'Chapter', 'Article', 'Scripture Citation'],
  WCOF: ['Westminster Confession of Faith', 'Chapter', 'Article', 'Scripture Citation'],
  HC: ['Heidelberg Catechism', "LORD's Day", 'Question and Answer', 'Scripture Citation'],
  WSC: ['Westminster Shorter Catechism', 'Question and Answer', 'Scripture Citation'],
  WLC: ['Westminster Larger Catechism', 'Question and Answer', 'Scripture Citation'],
  '39A': ['Thirty-nine Articles of Religion', 'Chapter'],
  TAR: ['Thirty-nine Articles of Religion', 'Chapter'],
  TAOR: ['Thirty-nine Articles of Religion', 'Chapter'],
  CD: ['Canons of Dort', 'Chapter'],
  COD: ['Canons of Dort', 'Chapter'],
  BCF: ['The Belgic Confession of Faith', 'Chapter'],
  TBCoF: ['The Belgic Confession of Faith', 'Chapter'],
  TBCOF: ['The Belgic Confession of Faith', 'Chapter'],
  BC: ['The Belgic Confession of Faith', 'Chapter'],
  '95T': ["Martin Luther's 95 theses"],
  ML9T: ["Martin Luther's 95 theses"],
  CFYC: ['Catechism for Young Children'],
  ALL: ['ALL'],
};

// maps each document's true canonical id (as it appears as the id prefix in
// contentById, e.g. "WCoF-1-2") to the URL slug used for its library pages.
export const slugByDocumentId: Record<string, string> = {
  WCoF: 'westminster-confession-of-faith',
  WLC: 'westminster-larger-catechism',
  WSC: 'westminster-shorter-catechism',
  HC: 'heidelberg-catechism',
  CoD: 'canons-of-dort',
  TBCoF: 'the-belgic-confession-of-faith',
  TAoR: 'thirty-nine-articles-of-religion',
  ML9t: 'martin-luthers-95-theses',
};

// inverse of slugByDocumentId: URL slug -> canonical document id.
export const documentIdBySlug: Record<string, string> = Object.fromEntries(
  Object.entries(slugByDocumentId).map(([id, slug]) => [slug, id]),
);

// canonical docIds in algolia 🤦
export const parentIdByAbbreviation: Record<string, string> = {
  WCF: 'WCoF',
  WCOF: 'WCoF',
  HC: 'HC',
  WLC: 'WLC',
  WSC: 'WSC',
  CD: 'CoD',
  COD: 'CoD',
  BCF: 'TBCoF',
  TAR: 'TAoR',
  '39A': 'TAoR',
  '95T': 'ML9t',
  ML9T: 'ML9t',
  CFYC: 'CfYC',
};

export const DOCUMENTS_WITHOUT_ARTICLES = [
  'ML9T',
  'BCF',
  'TBCoF',
  'TAR',
  'WLC',
  'WSC',
  'CFYC',
  'CfYC',
];

export const confessionIdsWithoutTitles = [
  'WSC',
  'WLC',
  'BCoF',
  'TBCoF',
  'TAoR',
  'ML9t',
  'CfYC',
];

export const excludedWordsInDocumentId = ['OF', 'THE'];

export const facetNamesByCanonicalDocId: Record<string, (string | string[])[]> = {
  WCF: ['chapter', 'article'],
  BCF: ['chapter'],
  HC: ['lords day', 'question'],
  CD: [['chapter', 'rejection'], ['chapter', 'article']],
  TAR: ['chapter'],
  ML9T: ['thesis'],
  WLC: ['question'],
  WSC: ['question'],
  CFYC: ['question'],
};

export const KEYWORDS = [
  'westminster standards',
  'three forms of unity',
  '3 forms of unity',
  'six forms of unity',
  '6 forms of unity',
];
