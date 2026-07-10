// Client-safe content access for the first program: WSC questions (the data
// the session teaches — bundled, it IS the program) and the authored prayers.
import wsc from '../../normalized-data/westminster/wsc.json';
import prayers from '../../content/programs/catechizing-shorter-catechism/prayers.json';
import { stripFootnoteMarkers } from './helpers';
import type { ConfessionDocumentJson } from './domain';

const wscDoc = wsc as unknown as ConfessionDocumentJson;

export interface ProgramQuestion {
  number: number;
  question: string;
  answer: string;
  /** OSIS proof-text refs, deduped, in footnote order */
  proofTexts: string[];
}

const QUESTION_PREFIX = /^Question\s\d+:\s*/;

export const getWscQuestion = (n: number): ProgramQuestion | null => {
  const entry = wscDoc.content.find((e) => e.number === n && !e.isParent);
  if (!entry) return null;
  return {
    number: n,
    question: (entry.title ?? '').replace(QUESTION_PREFIX, ''),
    answer: stripFootnoteMarkers(entry.text ?? ''),
    proofTexts: entry.verses ? Array.from(new Set(Object.values(entry.verses).flat())) : [],
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
