/**
 * Domain types, promoted from v1's global types/domain.d.ts into real
 * exported types. See docs/DOMAIN.md for the id grammar and the
 * document-alias vocabularies these shapes are keyed by.
 */

/**
 * A single node in a confession/catechism, as stored in
 * dataMapping/content-by-id.json and normalized-data/**.
 *
 * Ids are dash-delimited paths, e.g. "WCoF-1" (chapter), "WCoF-1-2" (article),
 * "CoD-1-articles-3" / "CoD-1-rejections-2" (Canons of Dort). The `parent`
 * pointer + id prefix encode an implicit tree over a flat map.
 */
export interface ConfessionEntry {
  /** Canonical id, e.g. "WCoF-1-2". The prefix is the canonical document id. */
  id: string;
  /** Parent id; a document-only parent (no dash, e.g. "WCoF") marks a top-level entry. */
  parent: string;
  /** Human-readable heading, e.g. "Chapter 1: Of the Holy Scripture". */
  title: string;
  /** True for structural/heading nodes (chapters, LORD's Days), false for leaf text entries. */
  isParent: boolean;
  /** The chapter/question/article number, when present. */
  number?: number;
  /** The confession text for leaf entries. */
  text?: string;
  /** Proof-text scripture citations (OSIS refs), keyed by footnote label. */
  verses?: Record<string, string[]>;
}

/** The flat id -> entry map that most components receive as `contentById`. */
export type ContentById = Record<string, ConfessionEntry>;

/** Result of loadConfessionContent(slug). */
export interface ConfessionContent {
  contentById: ContentById;
  /** The canonical document id derived from the data, e.g. "WCoF". */
  documentId: string;
}

/** Shape of one normalized-data/**.json document file. */
export interface ConfessionDocumentJson {
  title: string;
  type: string;
  content: ConfessionEntry[];
}

/**
 * Document metadata (the single source of truth in lib/catechisms.ts).
 * `itemLabel`/`totalItems` generalize over catechism "Questions", confession
 * "Chapters"/"Articles", and the theses.
 */
export interface CreedalDocument {
  id: string;
  name: string;
  shortName: string;
  totalItems: number;
  itemLabel: string;
  itemLabelPlural: string;
  type: 'catechism' | 'confession' | 'theses';
  tradition: string;
  description: string;
}

/** Children-tracking view of a catechism, derived from CreedalDocument. */
export interface Catechism {
  id: string;
  name: string;
  shortName: string;
  totalQuestions: number;
  description: string;
  /** Suggested age range, e.g. "8-12". */
  ageRange: string;
}

/** Long-form commentary post loaded from content/commentary/<entryId>.md. */
export interface Commentary {
  title: string | null;
  subtitle: string | null;
  author: string | null;
  /** ISO date string (YYYY-MM-DD) or null. */
  date: string | null;
  /** Markdown body. */
  body: string;
}

/**
 * The return type of parseFacets(). Each element is an Algolia facetFilter
 * string like "id:WCoF-1-2" or "document:...". A NESTED array of strings
 * expresses OR between those filters (Algolia's facetFilters semantics);
 * a bare string is an AND term.
 */
export type FacetFilter = string | string[];
export type FacetFilters = FacetFilter[];
