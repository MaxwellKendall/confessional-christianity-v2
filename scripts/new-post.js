#!/usr/bin/env node
/* eslint-disable no-console */

// Scaffolds a commentary post at content/commentary/<entry-id>.md, deriving the
// (non-obvious) entry id from a reader-facing URL or slug + path segments.
//
// Usage:
//   node scripts/new-post.js /westminster-shorter-catechism/1
//   node scripts/new-post.js westminster-shorter-catechism 1
//   node scripts/new-post.js westminster-confession-of-faith 1 2
//   node scripts/new-post.js canons-of-dort 1 articles 1
//   ...add --force to overwrite an existing file.

import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

// slug -> normalized-data JSON file. Keep in sync with confessionPathByName in
// dataMapping/index.js (that module is ESM, so it can't be required here).
const confessionPathByName = {
  'westminster-confession-of-faith': 'normalized-data/westminster/wcf.json',
  'westminster-larger-catechism': 'normalized-data/westminster/wlc.json',
  'westminster-shorter-catechism': 'normalized-data/westminster/wsc.json',
  'heidelberg-catechism': 'normalized-data/three-forms-of-unity/heidelberg-catechism.json',
  'canons-of-dort': 'normalized-data/three-forms-of-unity/canons-of-dort.json',
  'the-belgic-confession-of-faith': 'normalized-data/three-forms-of-unity/belgic-confession.json',
  'thirty-nine-articles-of-religion': 'normalized-data/anglican/39-articles.json',
  'martin-luthers-95-theses': 'normalized-data/reformation/95-theses.json',
};

const fail = (msg) => {
  console.error(`\n✖ ${msg}\n`);
  process.exit(1);
};

// --- parse args -------------------------------------------------------------
const rawArgs = process.argv.slice(2);
const force = rawArgs.includes('--force');
const args = rawArgs.filter((a) => a !== '--force');

if (args.length === 0) {
  fail('Provide a URL or slug + segments, e.g.\n'
    + '    node scripts/new-post.js /westminster-shorter-catechism/1\n'
    + '    node scripts/new-post.js westminster-confession-of-faith 1 2');
}

// Accept a full URL, a "/slug/1/2" path, or "slug 1 2" as separate args.
let parts;
if (args.length === 1 && args[0].includes('/')) {
  const withoutProtocol = args[0].replace(/^https?:\/\/[^/]+/, '');
  parts = withoutProtocol.split('/').filter(Boolean);
} else {
  parts = args;
}

const [slug, ...segments] = parts;

if (!confessionPathByName[slug]) {
  fail(`Unknown confession slug "${slug}".\nValid slugs:\n  ${Object.keys(confessionPathByName).join('\n  ')}`);
}
if (segments.length === 0) {
  fail(`No entry segments given. Point at a specific entry, e.g. "${slug} 1".`);
}

// --- load the confession and resolve the entry id ---------------------------
const jsonPath = path.join(process.cwd(), confessionPathByName[slug]);
const parsed = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const contentById = parsed.content.reduce((acc, item) => ({ ...acc, [item.id]: item }), {});

// documentId (e.g. WSC, WCoF) is the parent of any top-level entry.
const documentId = parsed.content.find((v) => v.parent.split('-').length === 1).parent;
const entryId = `${documentId}-${segments.join('-')}`;
const entry = contentById[entryId];

if (!entry) {
  fail(`No entry "${entryId}" exists in ${slug}.\n`
    + `Check the URL — segments were: ${segments.join(', ')}.`);
}

// --- write the scaffold -----------------------------------------------------
const dir = path.join(process.cwd(), 'content', 'commentary');
fs.mkdirSync(dir, { recursive: true });
const filePath = path.join(dir, `${entryId}.md`);

if (fs.existsSync(filePath) && !force) {
  fail(`${path.relative(process.cwd(), filePath)} already exists. Re-run with --force to overwrite.`);
}

let author = '';
try {
  author = execSync('git config user.name', { encoding: 'utf8' }).trim();
} catch (e) { /* no git identity; leave blank */ }

const today = new Date().toISOString().slice(0, 10);

// Include the entry text as an HTML comment so it's visible while writing but
// never rendered on the page.
// JSON.stringify yields a valid YAML double-quoted scalar, so titles that
// contain colons (e.g. "Question 1: ...") don't break frontmatter parsing.
const scaffold = `---
title: ${JSON.stringify(entry.title || '')}
subtitle: ""
author: ${JSON.stringify(author)}
date: ${today}
---

<!-- Entry: ${entry.title || entryId}
${(entry.text || '').trim()}
-->

Write your commentary here.
`;

fs.writeFileSync(filePath, scaffold);

const urlPath = `/${slug}/${segments.join('/')}`;
console.log(`\n✔ Created ${path.relative(process.cwd(), filePath)}`);
console.log(`  Entry:   ${entry.title || entryId}`);
console.log(`  Preview: http://localhost:1517${urlPath}\n`);
