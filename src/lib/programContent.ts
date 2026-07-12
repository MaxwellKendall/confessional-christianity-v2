// Client-safe content access for the first program: WSC questions (the data
// the session teaches — bundled, it IS the program) and the authored prayers.
import wsc from '../../normalized-data/westminster/wsc.json';
import prayers from '../../content/programs/catechizing-shorter-catechism/prayers.json';
import { entryQuoteSegments, proofTextGroups, type ProofTextGroup, type TextSegment } from './entryDisplay';
import { stripFootnoteMarkers } from './helpers';
import type { ConfessionDocumentJson, ConfessionEntry } from './domain';

const wscDoc = wsc as unknown as ConfessionDocumentJson;

export interface ProgramQuestion {
  number: number;
  question: string;
  answer: string;
  /** OSIS proof-text refs, deduped, in footnote order */
  proofTexts: string[];
}

const QUESTION_PREFIX = /^Question\s\d+:\s*/;

const wscEntry = (n: number): ConfessionEntry | null => wscDoc.content
  .find((e) => e.number === n && !e.isParent) ?? null;

export const getWscQuestion = (n: number): ProgramQuestion | null => {
  const entry = wscEntry(n);
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
export const wscEntryId = (n: number): string | null => wscEntry(n)?.id ?? null;

// Per-clause citation markers for the answer (mockup 8a): the answer's own
// segments (so markers render inline) plus the proof texts each marker
// supports, so a tap can swap in that clause's specific verse.
export const getWscQuestionCitations = (n: number): {
  answerSegments: TextSegment[];
  groups: ProofTextGroup[];
} | null => {
  const entry = wscEntry(n);
  if (!entry) return null;
  const [, answerLine] = entryQuoteSegments(entry);
  return {
    answerSegments: (answerLine ?? []).filter((segment) => segment.text !== 'A. '),
    groups: proofTextGroups(entry),
  };
};

const prayersByNumber = prayers as Record<string, string>;

// Authored prayers are written progressively (PRD §5.1); null means
// "prayer not yet written", which the program surfaces honestly.
export const getPrayer = (questionNumber: number, childName: string): string | null => {
  const raw = prayersByNumber[String(questionNumber)];
  if (!raw || questionNumber.toString().startsWith('_')) return null;
  return raw.replaceAll('{name}', childName);
};

export const hasPrayer = (questionNumber: number): boolean => Boolean(
  prayersByNumber[String(questionNumber)],
);
