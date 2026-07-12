#!/usr/bin/env node
import { promises as fs } from 'node:fs';
import {
  DEFAULT_SLUG,
  approvedMap,
  compiledFile,
  readPrayers,
} from './prayers-lib.mjs';

const args = process.argv.slice(2);
const readArg = (name, fallback = null) => {
  const idx = args.indexOf(name);
  return idx === -1 ? fallback : args[idx + 1];
};

const slug = readArg('--slug', DEFAULT_SLUG);
const output = compiledFile(slug);
const approved = await approvedMap(slug);
const prayers = await readPrayers(slug);

const payload = {
  _comment: 'Compiled from approved Markdown prayers. Edit content/programs/<slug>/prayers/*.md, then run npm run prayers:compile.',
  ...Object.fromEntries(
    Object.entries(approved).sort(([a], [b]) => Number(a) - Number(b)),
  ),
};

await fs.writeFile(output, `${JSON.stringify(payload, null, 2)}\n`, 'utf8');

const approvedCount = Object.keys(approved).length;
const draftCount = prayers.filter((p) => p.status === 'draft').length;
console.log(`Compiled ${approvedCount} approved prayers to ${output}`);
if (draftCount) console.log(`Skipped ${draftCount} draft prayers`);
