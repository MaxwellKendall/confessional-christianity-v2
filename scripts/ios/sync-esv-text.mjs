#!/usr/bin/env node
// Pre-fetches ESV passage text for every proof-text osis reference cited
// across all bundled documents, and bakes it into DomainKit's resources as
// bible-text.json. This is the closed universe of osis refs the app can
// ever push to (Session proof-texts, Library entry citations, and Search's
// "Cited by"/scripture links all resolve to a ref in this set), so bundling
// it lets Session/Library/Scripture read passage text fully offline — see
// the plan's Phase 1 note on baking ESV text into the content bundle.
//
// Calls api.esv.org directly (not the deployed /api/esv proxy): an early
// version of this script went through the proxy at concurrency 8 and got
// silently throttled by the ESV API almost immediately (route.ts collapses
// any non-ok upstream response to `{text: null}`, so the throttling was
// invisible until nearly the whole run had failed). Going direct lets this
// script see real 429s and back off properly; osis -> ESV citation
// conversion is reimplemented here (mirrors src/lib/bible.ts's
// parseOsisBibleReference) since that's the one piece the proxy was doing.
//
// Resumable: re-running skips osis refs bible-text.json already has, so a
// partial/interrupted run (or a re-run after new refs are added to
// scripts/deduped-bible-verses.json) only fetches what's missing. A
// partially-populated bible-text.json is safe to ship as-is — EsvClient
// falls back to a live fetch for any ref this file doesn't have, so
// incomplete coverage only means less of the app works offline, not that
// anything breaks. Re-run this any time to top it up further; ESV's limits
// (5,000/day, 1,000/hour, 60/minute) mean a full pass from empty takes over
// an hour at this script's pace, so it's fine to stop it early and resume
// later.
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
process.loadEnvFile(path.join(repoRoot, '.env.local'));

const versesPath = path.join(repoRoot, 'scripts/deduped-bible-verses.json');
const outputPath = path.join(
  repoRoot,
  'ios/DomainKit/Sources/DomainKit/BundledContent/bible-text.json',
);
const versionPath = path.join(
  repoRoot,
  'ios/DomainKit/Sources/DomainKit/BundledContent/content-version.json',
);

const ESV_API_KEY = process.env.ESV_API_KEY;
if (!ESV_API_KEY) {
  console.error('ESV_API_KEY not set (checked .env.local)');
  process.exit(1);
}

const bibleBookByAbbreviation = {
  Gen: 'Genesis', Exod: 'Exodus', Lev: 'Leviticus', Num: 'Numbers', Deut: 'Deuteronomy',
  Josh: 'Joshua', Judg: 'Judges', Ruth: 'Ruth', '1Sam': '1 Samuel', '2Sam': '2 Samuel',
  '1Kgs': '1 Kings', '2Kgs': '2 Kings', '1Chr': '1 Chronicles', '2Chr': '2 Chronicles',
  Ezra: 'Ezra', Neh: 'Nehemiah', Esth: 'Esther', Job: 'Job', Ps: 'Psalms', Prov: 'Proverbs',
  Eccl: 'Ecclesiastes', Song: 'Song of Solomon', Isa: 'Isaiah', Jer: 'Jeremiah',
  Lam: 'Lamentations', Ezek: 'Ezekiel', Dan: 'Daniel', Hos: 'Hosea', Joel: 'Joel',
  Amos: 'Amos', Obad: 'Obadiah', Jonah: 'Jonah', Mic: 'Micah', Nah: 'Nahum', Hab: 'Habakkuk',
  Zeph: 'Zephaniah', Hag: 'Haggai', Zech: 'Zechariah', Mal: 'Malachi', New: 'Testament',
  Matt: 'Matthew', Mark: 'Mark', Luke: 'Luke', John: 'John', Acts: 'Acts', Rom: 'Romans',
  '1Cor': '1 Corinthians', '2Cor': '2 Corinthians', Gal: 'Galatians', Eph: 'Ephesians',
  Phil: 'Philippians', Col: 'Colossians', '1Thess': '1 Thessalonians', '2Thess': '2 Thessalonians',
  '1Tim': '1 Timothy', '2Tim': '2 Timothy', Titus: 'Titus', Phlm: 'Philemon', Heb: 'Hebrews',
  Jas: 'James', '1Pet': '1 Peter', '2Pet': '2 Peter', '1John': '1 John', '2John': '2 John',
  '3John': '3 John', Jude: 'Jude', Rev: 'Revelation',
};

const parseOsisBibleReference = (osisStr) => {
  if (!osisStr) return '';
  if (osisStr.includes(',')) {
    return osisStr.split(',').map(parseOsisBibleReference).join(',');
  }
  const splitStr = osisStr.split('-');
  return splitStr.reduce((acc, str, i, srcArr) => {
    const bookChapterVerse = str.split('.');
    const book = bibleBookByAbbreviation[bookChapterVerse[0]];
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

// ESV API's documented limits: 5,000/day, 1,000/hour, 60/minute. A single
// worker at 4s/request averages 900/hour and 15/minute — comfortably under
// all three, so retries below are for genuine transient errors, not for
// riding out a throttle.
const CONCURRENCY = 1;
const MIN_DELAY_MS = 4000;
const MAX_RETRIES = 3;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function fetchText(osis) {
  const citation = parseOsisBibleReference(osis);
  const params = new URLSearchParams({
    q: citation,
    'include-passage-references': 'false',
    'include-verse-numbers': 'false',
    'include-footnotes': 'false',
    'include-headings': 'false',
    'include-short-copyright': 'false',
  });
  const url = `https://api.esv.org/v3/passage/text/?${params}`;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    let response;
    try {
      response = await fetch(url, { headers: { Authorization: `Token ${ESV_API_KEY}` } });
    } catch (error) {
      if (attempt === MAX_RETRIES) {
        console.warn(`  network error ${osis}: ${error.message}`);
        return null;
      }
      await sleep(1000 * 2 ** attempt);
      continue;
    }

    if (response.status === 429) {
      const retryAfter = Number(response.headers.get('retry-after')) || 2 ** attempt;
      if (attempt === MAX_RETRIES) {
        console.warn(`  still throttled on ${osis} after ${MAX_RETRIES} attempts`);
        return null;
      }
      await sleep(retryAfter * 1000);
      continue;
    }

    if (!response.ok) {
      if (attempt === MAX_RETRIES) {
        console.warn(`  HTTP ${response.status} for ${osis}`);
        return null;
      }
      await sleep(1000 * 2 ** attempt);
      continue;
    }

    const data = await response.json();
    const text = data.passages?.[0]?.replace(/\s+/g, ' ').trim() ?? null;
    if (!text) console.warn(`  no passage returned for ${osis} (${citation})`);
    return text;
  }
  return null;
}

const verses = JSON.parse(await fs.readFile(versesPath, 'utf8'));
const allOsisRefs = Object.keys(verses);

let results = {};
try {
  results = JSON.parse(await fs.readFile(outputPath, 'utf8'));
} catch {
  // first run
}

const alreadyHave = Object.keys(results).length;
const queue = allOsisRefs.filter((osis) => !(osis in results));
console.log(
  `${allOsisRefs.length} total refs, ${alreadyHave} already bundled, fetching ${queue.length} more ` +
  `(concurrency ${CONCURRENCY})...`,
);

let completed = 0;
let missing = 0;

async function worker(q) {
  while (q.length) {
    const osis = q.pop();
    const text = await fetchText(osis);
    if (text) {
      results[osis] = text;
    } else {
      missing++;
    }
    completed++;
    if (completed % 50 === 0 || completed === queue.length) {
      console.log(`  ${completed}/${queue.length} fetched (${missing} missing so far)`);
      const sorted = Object.fromEntries(Object.keys(results).sort().map((k) => [k, results[k]]));
      await fs.writeFile(outputPath, `${JSON.stringify(sorted, null, 2)}\n`, 'utf8');
    }
    await sleep(MIN_DELAY_MS);
  }
}

await Promise.all(Array.from({ length: CONCURRENCY }, () => worker(queue)));

const sorted = Object.fromEntries(Object.keys(results).sort().map((k) => [k, results[k]]));
await fs.writeFile(outputPath, `${JSON.stringify(sorted, null, 2)}\n`, 'utf8');

let version = {};
try {
  version = JSON.parse(await fs.readFile(versionPath, 'utf8'));
} catch {
  // sync-content.mjs hasn't run yet; start fresh.
}
version.esvTextSyncedAt = new Date().toISOString();
version.files = Array.from(new Set([...(version.files ?? []), 'bible-text.json']));
await fs.writeFile(versionPath, `${JSON.stringify(version, null, 2)}\n`, 'utf8');

const stillMissing = allOsisRefs.length - Object.keys(results).length;
console.log(
  `Wrote ${Object.keys(results).length}/${allOsisRefs.length} verses to ` +
  `${path.relative(repoRoot, outputPath)}` +
  (stillMissing ? ` (${stillMissing} still missing — re-run to retry)` : ''),
);
