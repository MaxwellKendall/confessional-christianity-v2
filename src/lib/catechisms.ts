// All creedal documents. This is the single source of truth for every
// document's shared metadata (name, shortName, item count, description,
// tradition). The children-tracking CATECHISMS registry below is *derived*
// from this map rather than duplicated, so the two can't drift out of sync.
// See docs/DOMAIN.md.
import { parentIdByAbbreviation, slugByDocumentId } from './dataMapping';
import type { Catechism, CreedalDocument } from './domain';

export const CREEDAL_DOCUMENTS: Record<string, CreedalDocument> = {
  // Catechisms (Question & Answer format)
  WSC: {
    id: 'WSC',
    name: 'Westminster Shorter Catechism',
    shortName: 'WSC',
    totalItems: 107,
    itemLabel: 'Question',
    itemLabelPlural: 'Questions',
    type: 'catechism',
    tradition: 'Westminster Standards',
    description: 'A summary of doctrine intended for those beginning their Christian education',
  },
  WLC: {
    id: 'WLC',
    name: 'Westminster Larger Catechism',
    shortName: 'WLC',
    totalItems: 196,
    itemLabel: 'Question',
    itemLabelPlural: 'Questions',
    type: 'catechism',
    tradition: 'Westminster Standards',
    description: 'A more comprehensive catechism for those who have profited by the Shorter Catechism',
  },
  CFYC: {
    id: 'CfYC',
    name: 'Catechism for Young Children',
    shortName: 'CfYC',
    totalItems: 145,
    itemLabel: 'Question',
    itemLabelPlural: 'Questions',
    type: 'catechism',
    tradition: 'Other',
    description: 'An introductory catechism designed for young children',
  },
  HC: {
    id: 'HC',
    name: 'Heidelberg Catechism',
    shortName: 'HC',
    totalItems: 129,
    itemLabel: 'Question',
    itemLabelPlural: 'Questions',
    type: 'catechism',
    tradition: 'Three Forms of Unity',
    description: 'A Protestant catechism taking the form of a series of questions and answers',
  },
  // Confessions (Chapter format)
  WCF: {
    id: 'WCF',
    name: 'Westminster Confession of Faith',
    shortName: 'WCF',
    totalItems: 33,
    itemLabel: 'Chapter',
    itemLabelPlural: 'Chapters',
    type: 'confession',
    tradition: 'Westminster Standards',
    description: 'The principal confessional standard of Presbyterian churches worldwide',
  },
  BCF: {
    id: 'BCF',
    name: 'Belgic Confession of Faith',
    shortName: 'BCF',
    totalItems: 37,
    itemLabel: 'Article',
    itemLabelPlural: 'Articles',
    type: 'confession',
    tradition: 'Three Forms of Unity',
    description: 'One of the Three Forms of Unity, a confession of the Reformed churches',
  },
  CD: {
    id: 'CD',
    name: 'Canons of Dort',
    shortName: 'CD',
    totalItems: 4,
    itemLabel: 'Head of Doctrine',
    itemLabelPlural: 'Heads of Doctrine',
    type: 'confession',
    tradition: 'Three Forms of Unity',
    description: 'The judgment of the Synod of Dort on the Five Articles of the Remonstrants',
  },
  TAR: {
    id: 'TAR',
    name: 'Thirty-Nine Articles',
    shortName: '39A',
    totalItems: 39,
    itemLabel: 'Article',
    itemLabelPlural: 'Articles',
    type: 'confession',
    tradition: 'Anglican',
    description: 'The defining statements of Anglican doctrine',
  },
  '95T': {
    id: '95T',
    name: 'Ninety-Five Theses',
    shortName: '95T',
    totalItems: 95,
    itemLabel: 'Thesis',
    itemLabelPlural: 'Theses',
    type: 'theses',
    tradition: 'Reformation',
    description: "Martin Luther's propositions that sparked the Protestant Reformation",
  },
};

// Catechisms available for children's progress tracking. Derived from
// CREEDAL_DOCUMENTS so name/count/description stay in one place; the only
// catechism-specific field is the suggested ageRange overlay below. The
// `totalQuestions` alias is preserved for existing consumers/tests.
const CATECHISM_AGE_RANGES: Record<string, string> = {
  WSC: '8-12',
  WLC: '12+',
  CFYC: '4-8',
  HC: '10+',
};

export const CATECHISMS: Record<string, Catechism> = Object.fromEntries(
  Object.entries(CATECHISM_AGE_RANGES).map(([key, ageRange]) => {
    const doc = CREEDAL_DOCUMENTS[key];
    return [key, {
      id: doc.id,
      name: doc.name,
      shortName: doc.shortName,
      totalQuestions: doc.totalItems,
      description: doc.description,
      ageRange,
    }];
  }),
);

export const getCatechismById = (id: string): Catechism | null => {
  const upperCaseId = id?.toUpperCase();
  if (upperCaseId === 'CFYC') return CATECHISMS.CFYC;
  return CATECHISMS[upperCaseId] || null;
};

export const getDocumentById = (id: string): CreedalDocument | null => {
  if (!id) return null;
  const upperCaseId = id.toUpperCase();
  if (upperCaseId === 'CFYC') return CREEDAL_DOCUMENTS.CFYC;
  return CREEDAL_DOCUMENTS[upperCaseId] || null;
};

export const getCatechismList = (): Catechism[] => Object.values(CATECHISMS);

export const getDocumentList = (): CreedalDocument[] => Object.values(CREEDAL_DOCUMENTS);

export interface TraditionGroup {
  tradition: string;
  documents: CreedalDocument[];
}

export const getDocumentsByTradition = (): TraditionGroup[] => {
  const documents = Object.values(CREEDAL_DOCUMENTS);
  const grouped: Record<string, CreedalDocument[]> = {};

  documents.forEach((doc) => {
    if (!grouped[doc.tradition]) {
      grouped[doc.tradition] = [];
    }
    grouped[doc.tradition].push(doc);
  });

  // Return in a specific order
  return [
    { tradition: 'Westminster Standards', documents: grouped['Westminster Standards'] || [] },
    { tradition: 'Three Forms of Unity', documents: grouped['Three Forms of Unity'] || [] },
    { tradition: 'Anglican', documents: grouped['Anglican'] || [] },
    { tradition: 'Reformation', documents: grouped['Reformation'] || [] },
    { tradition: 'Other', documents: grouped['Other'] || [] },
  ].filter((g) => g.documents.length > 0);
};

// Resolves a document abbreviation + item number to the canonical library
// entry page, e.g. ('WSC', 12) -> /library/westminster-shorter-catechism/12.
// v1 generated /?search= links here; v2's canonical pages replace them.
export const generateDocumentLink = (documentId: string, itemNumber: number): string => {
  const canonicalId = parentIdByAbbreviation[documentId?.toUpperCase()] ?? documentId;
  const slug = slugByDocumentId[canonicalId];
  if (!slug) return `/search?q=${encodeURIComponent(`${documentId}.${itemNumber}`)}`;
  return `/library/${slug}/${itemNumber}`;
};

export const generateCatechismLink = (
  catechismId: string,
  questionNumber: number,
): string => generateDocumentLink(catechismId, questionNumber);

export const calculateProgress = (
  currentQuestion: number | null | undefined,
  totalQuestions: number | null | undefined,
): number => {
  if (!currentQuestion || !totalQuestions) return 0;
  return Math.round((currentQuestion / totalQuestions) * 100);
};
