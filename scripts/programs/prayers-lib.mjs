// Shared helpers for the prayer authoring pipeline (scripts/programs/*).
//
// The authoring source of truth is one Markdown file per catechism question
// at content/programs/<slug>/prayers/<n>.md, its frontmatter carrying the
// review status. compile-prayers.mjs distills the *approved* files into the
// runtime content/programs/<slug>/prayers.json that the app statically
// imports — so unreviewed drafts never reach a family.
//
// Standalone by design: no imports from src/ (which is TypeScript and part of
// the Next build), so every script here runs under plain `node`, like the
// rest of scripts/.
import path from 'node:path';
import { promises as fs } from 'node:fs';
import { fileURLToPath } from 'node:url';
import matter from 'gray-matter';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(HERE, '..', '..');
export const PROGRAMS_DIR = path.join(REPO_ROOT, 'content', 'programs');

export const DEFAULT_SLUG = 'catechizing-shorter-catechism';

export const prayerDir = (slug) => path.join(PROGRAMS_DIR, slug, 'prayers');
export const prayerFile = (slug, n) => path.join(prayerDir(slug), `${n}.md`);
export const compiledFile = (slug) => path.join(PROGRAMS_DIR, slug, 'prayers.json');

// ---------------------------------------------------------------------------
// WSC source content — the question, answer, and proof-text references a
// prayer is written to accompany. Ported from src/lib/bible.ts so the
// generator can pass human-readable citations without importing TypeScript.
// ---------------------------------------------------------------------------
const bibleBookByAbbreviation = {
  Gen: 'Genesis', Exod: 'Exodus', Lev: 'Leviticus', Num: 'Numbers',
  Deut: 'Deuteronomy', Josh: 'Joshua', Judg: 'Judges', Ruth: 'Ruth',
  '1Sam': '1 Samuel', '2Sam': '2 Samuel', '1Kgs': '1 Kings', '2Kgs': '2 Kings',
  '1Chr': '1 Chronicles', '2Chr': '2 Chronicles', Ezra: 'Ezra', Neh: 'Nehemiah',
  Esth: 'Esther', Job: 'Job', Ps: 'Psalms', Prov: 'Proverbs', Eccl: 'Ecclesiastes',
  Song: 'Song of Solomon', Isa: 'Isaiah', Jer: 'Jeremiah', Lam: 'Lamentations',
  Ezek: 'Ezekiel', Dan: 'Daniel', Hos: 'Hosea', Joel: 'Joel', Amos: 'Amos',
  Obad: 'Obadiah', Jonah: 'Jonah', Mic: 'Micah', Nah: 'Nahum', Hab: 'Habakkuk',
  Zeph: 'Zephaniah', Hag: 'Haggai', Zech: 'Zechariah', Mal: 'Malachi',
  Matt: 'Matthew', Mark: 'Mark', Luke: 'Luke', John: 'John', Acts: 'Acts',
  Rom: 'Romans', '1Cor': '1 Corinthians', '2Cor': '2 Corinthians',
  Gal: 'Galatians', Eph: 'Ephesians', Phil: 'Philippians', Col: 'Colossians',
  '1Thess': '1 Thessalonians', '2Thess': '2 Thessalonians', '1Tim': '1 Timothy',
  '2Tim': '2 Timothy', Titus: 'Titus', Phlm: 'Philemon', Heb: 'Hebrews',
  Jas: 'James', '1Pet': '1 Peter', '2Pet': '2 Peter', '1John': '1 John',
  '2John': '2 John', '3John': '3 John', Jude: 'Jude', Rev: 'Revelation',
};

export const parseOsisBibleReference = (osisStr) => {
  if (!osisStr) return '';
  if (osisStr.includes(',')) {
    return osisStr.split(',').map((s) => parseOsisBibleReference(s)).join(',');
  }
  const splitStr = osisStr.split('-');
  return splitStr.reduce((acc, str, i, srcArr) => {
    const bookChapterVerse = str.split('.');
    const book = bibleBookByAbbreviation[bookChapterVerse[0]] ?? bookChapterVerse[0];
    const chapterVerse = bookChapterVerse.slice(1).join(':');
    if (i === 0) return `${book} ${chapterVerse}`;
    const [prevBook, prevChapter] = srcArr[i - 1].split('.');
    if (prevBook === bookChapterVerse[0] && prevChapter === bookChapterVerse[1]) {
      return `${acc}-${bookChapterVerse[2]}`;
    }
    if (prevBook === bookChapterVerse[0]) return `${acc}-${chapterVerse}`;
    return `${acc} - ${book} ${chapterVerse}`;
  }, '');
};

const stripFootnoteMarkers = (text = '') => text
  .replace(/\[[a-zA-Z0-9]+\]/g, '')
  .replace(/\s+/g, ' ')
  .trim();

const QUESTION_PREFIX = /^Question\s\d+:\s*/;

let wscCache;
const loadWsc = async () => {
  if (!wscCache) {
    const raw = await fs.readFile(
      path.join(REPO_ROOT, 'normalized-data', 'westminster', 'wsc.json'),
      'utf8',
    );
    wscCache = JSON.parse(raw);
  }
  return wscCache;
};

export const getQuestion = async (n) => {
  const doc = await loadWsc();
  const entry = doc.content.find((e) => e.number === n && !e.isParent);
  if (!entry) return null;
  const proofTexts = entry.verses
    ? [...new Set(Object.values(entry.verses).flat())].map(parseOsisBibleReference)
    : [];
  return {
    number: n,
    question: (entry.title ?? '').replace(QUESTION_PREFIX, ''),
    answer: stripFootnoteMarkers(entry.text ?? ''),
    proofTexts,
  };
};

export const allQuestionNumbers = async () => {
  const doc = await loadWsc();
  return doc.content
    .filter((e) => !e.isParent && typeof e.number === 'number')
    .map((e) => e.number)
    .sort((a, b) => a - b);
};

// ---------------------------------------------------------------------------
// Prayer files
// ---------------------------------------------------------------------------
export const readPrayers = async (slug) => {
  let files;
  try {
    files = await fs.readdir(prayerDir(slug));
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  const out = [];
  for (const f of files) {
    if (!f.endsWith('.md')) continue;
    const raw = await fs.readFile(path.join(prayerDir(slug), f), 'utf8');
    const { data, content } = matter(raw);
    out.push({
      question: Number(data.question ?? f.replace(/\.md$/, '')),
      status: data.status ?? 'draft',
      source: data.source ?? 'human',
      model: data.model ?? null,
      generated: data.generated ?? null,
      body: content.trim(),
      file: f,
    });
  }
  return out.sort((a, b) => a.question - b.question);
};

export const writePrayer = async (slug, n, {
  body, status = 'draft', source = 'human', model = null, generated = null,
}) => {
  await fs.mkdir(prayerDir(slug), { recursive: true });
  const data = { question: n, status, source };
  if (source === 'llm') {
    data.model = model;
    data.generated = generated ?? new Date().toISOString().slice(0, 10);
  }
  await fs.writeFile(prayerFile(slug, n), matter.stringify(`${body.trim()}\n`, data), 'utf8');
};

// question number -> prayer body, approved only. The compile target.
export const approvedMap = async (slug) => {
  const prayers = await readPrayers(slug);
  const map = {};
  for (const p of prayers) if (p.status === 'approved') map[p.question] = p.body;
  return map;
};

// Parses "11", "11,12,15", and "11-20" into a sorted, de-duplicated list.
export const parseNumberList = (spec) => {
  const nums = new Set();
  for (const part of String(spec).split(',')) {
    const range = part.match(/^(\d+)\s*-\s*(\d+)$/);
    if (range) {
      const [from, to] = [Number(range[1]), Number(range[2])].sort((a, b) => a - b);
      for (let n = from; n <= to; n += 1) nums.add(n);
    } else if (part.trim()) {
      nums.add(Number(part.trim()));
    }
  }
  if ([...nums].some((n) => !Number.isInteger(n) || n < 1)) {
    throw new Error(`Invalid question list: ${spec}`);
  }
  return [...nums].sort((a, b) => a - b);
};
