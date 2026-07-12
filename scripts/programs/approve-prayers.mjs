#!/usr/bin/env node
import {
  DEFAULT_SLUG,
  parseNumberList,
  readPrayers,
  writePrayer,
} from './prayers-lib.mjs';

const args = process.argv.slice(2);
const readArg = (name, fallback = null) => {
  const idx = args.indexOf(name);
  return idx === -1 ? fallback : args[idx + 1];
};

const slug = readArg('--slug', DEFAULT_SLUG);
const spec = readArg('--questions');
if (!spec) throw new Error('Pass --questions with a number list, for example --questions 11 or --questions 11-15.');

const requested = new Set(parseNumberList(spec));
const prayers = await readPrayers(slug);
const byQuestion = new Map(prayers.map((p) => [p.question, p]));

for (const n of requested) {
  const prayer = byQuestion.get(n);
  if (!prayer) throw new Error(`No prayer file exists for Q${n}.`);
  await writePrayer(slug, n, {
    ...prayer,
    status: 'approved',
  });
  console.log(`Approved Q${n}`);
}
