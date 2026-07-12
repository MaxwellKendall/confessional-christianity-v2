// Client-safe content access for programs: catechism questions (the data a
// session teaches — bundled, it IS the program) and the authored prayers.
// Every program is a catechism today (WSC, CfYC, ...); each just points at
// its own normalized-data document and its own prayers file, statically
// imported so the bundler traces the data directly — a dynamic fs read
// breaks in Vercel's serverless bundles (see confessionContent.ts).
import wsc from '../../normalized-data/westminster/wsc.json';
import wlc from '../../normalized-data/westminster/wlc.json';
import heidelbergCatechism from '../../normalized-data/three-forms-of-unity/heidelberg-catechism.json';
import catechismYoungChildren from '../../normalized-data/miscellany/catechism-young-children.json';
import wscPrayers from '../../content/programs/catechizing-shorter-catechism/prayers.json';
import { entryQuoteSegments, proofTextGroups, type ProofTextGroup, type TextSegment } from './entryDisplay';
import { stripFootnoteMarkers } from './helpers';
import type { ConfessionDocumentJson, ConfessionEntry } from './domain';

// Add an entry here (and to PROGRAMS in programs.ts) for each new catechism
// program — same two-line shape as CFYC.
export type ContentId = 'WSC' | 'WLC' | 'HC' | 'CFYC';

const DOCS: Record<ContentId, ConfessionDocumentJson> = {
  WSC: wsc as unknown as ConfessionDocumentJson,
  WLC: wlc as unknown as ConfessionDocumentJson,
  HC: heidelbergCatechism as unknown as ConfessionDocumentJson,
  CFYC: catechismYoungChildren as unknown as ConfessionDocumentJson,
};

/** The two `ProgramDefinition` fields this module needs — kept structural
 * (rather than importing the type from programs.ts) to avoid a circular
 * import, since programs.ts imports `ContentId` from here. */
interface ProgramRef {
  contentId: ContentId;
  slug: string;
}

export interface ProgramQuestion {
  number: number;
  question: string;
  answer: string;
  /** OSIS proof-text refs, deduped, in footnote order */
  proofTexts: string[];
}

const QUESTION_PREFIX = /^Question\s\d+:\s*/;
const QUESTION_NUMBER = /^Question\s(\d+):/;

// The question number lives in `entry.number` for every catechism except the
// Heidelberg — its `number` is the raw content-array position (Lord's Day
// headers share the sequence), so the traditional Q number has to come from
// the title instead. Reading the title everywhere keeps this one lookup, not
// a per-catechism branch.
const questionNumberOf = (entry: ConfessionEntry): number | null => {
  const match = entry.title?.match(QUESTION_NUMBER);
  return match ? Number(match[1]) : entry.number ?? null;
};

const findEntry = (contentId: ContentId, n: number): ConfessionEntry | null => DOCS[contentId].content
  .find((e) => !e.isParent && questionNumberOf(e) === n) ?? null;

export const getQuestion = (program: ProgramRef, n: number): ProgramQuestion | null => {
  const entry = findEntry(program.contentId, n);
  if (!entry) return null;
  return {
    number: n,
    question: (entry.title ?? '').replace(QUESTION_PREFIX, ''),
    answer: stripFootnoteMarkers(entry.text ?? ''),
    proofTexts: entry.verses ? Array.from(new Set(Object.values(entry.verses).flat())) : [],
  };
};

/** The catechism entry id (e.g. "WSC-1") a question corresponds to — used to
 * key reflections and clause-level citations, which key off the raw entry. */
export const entryId = (program: ProgramRef, n: number): string | null => (
  findEntry(program.contentId, n)?.id ?? null
);

// Per-clause citation markers for the answer (mockup 8a): the answer's own
// segments (so markers render inline) plus the proof texts each marker
// supports, so a tap can swap in that clause's specific verse.
export const getQuestionCitations = (program: ProgramRef, n: number): {
  answerSegments: TextSegment[];
  groups: ProofTextGroup[];
} | null => {
  const entry = findEntry(program.contentId, n);
  if (!entry) return null;
  const [, answerLine] = entryQuoteSegments(entry);
  return {
    answerSegments: (answerLine ?? []).filter((segment) => segment.text !== 'A. '),
    groups: proofTextGroups(entry),
  };
};

// Each program's authored prayers, keyed by its slug — add an entry here
// alongside content/programs/<slug>/prayers/ once a program has any.
const PRAYERS: Record<string, Record<string, string>> = {
  'catechizing-shorter-catechism': wscPrayers as Record<string, string>,
};

// Authored prayers are written progressively (PRD §5.1); null means
// "prayer not yet written", which the program surfaces honestly.
export const getPrayer = (program: ProgramRef, questionNumber: number, childName: string): string | null => {
  const raw = PRAYERS[program.slug]?.[String(questionNumber)];
  if (!raw || questionNumber.toString().startsWith('_')) return null;
  return raw.replaceAll('{name}', childName);
};

export const hasPrayer = (program: ProgramRef, questionNumber: number): boolean => Boolean(
  PRAYERS[program.slug]?.[String(questionNumber)],
);
