#!/usr/bin/env node
// Syncs the static content DomainKit (ios/DomainKit) bundles on-device into
// its package resources. Mirrors what src/lib/programContent.ts statically
// imports today — the iOS app's source of truth is this repo, never the
// ios/DomainKit/Sources/DomainKit/Resources folder directly (generated,
// never hand-edited).
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
// Deliberately not named "Resources": a subdirectory literally named
// "Resources" inside a .bundle trips up codesign's old-style-bundle format
// detection on current Xcode/macOS (confirmed while wiring up the iOS build —
// codesign rejects the bundle as "unrecognized, invalid, or unsuitable").
const resourcesRoot = path.join(repoRoot, 'ios/DomainKit/Sources/DomainKit/BundledContent');

// Every file DomainKit needs, source path -> destination path (both relative
// to their respective roots). Extend this list as more programs/documents
// are ported to the iOS app.
const FILES = [
  ['normalized-data/westminster/wsc.json', 'normalized-data/westminster/wsc.json'],
  ['normalized-data/westminster/wlc.json', 'normalized-data/westminster/wlc.json'],
  ['normalized-data/westminster/wcf.json', 'normalized-data/westminster/wcf.json'],
  ['normalized-data/three-forms-of-unity/heidelberg-catechism.json', 'normalized-data/three-forms-of-unity/heidelberg-catechism.json'],
  ['normalized-data/three-forms-of-unity/canons-of-dort.json', 'normalized-data/three-forms-of-unity/canons-of-dort.json'],
  ['normalized-data/three-forms-of-unity/belgic-confession.json', 'normalized-data/three-forms-of-unity/belgic-confession.json'],
  ['normalized-data/anglican/39-articles.json', 'normalized-data/anglican/39-articles.json'],
  ['normalized-data/reformation/95-theses.json', 'normalized-data/reformation/95-theses.json'],
  ['normalized-data/miscellany/catechism-young-children.json', 'normalized-data/miscellany/catechism-young-children.json'],
  ['content/programs/catechizing-shorter-catechism/prayers.json', 'content/programs/catechizing-shorter-catechism/prayers.json'],
];

// content/devotions holds every authored devotion and series manifest, and
// content/commentary holds every authored reflection/commentary essay —
// both are open-ended (grow as new essays/devotions are authored) rather
// than a fixed subset, so they're copied recursively rather than enumerated
// file-by-file.
const DIRECTORIES = [
  ['content/devotions', 'content/devotions'],
  ['content/commentary', 'content/commentary'],
];

for (const [src, dest] of FILES) {
  const srcPath = path.join(repoRoot, src);
  const destPath = path.join(resourcesRoot, dest);
  await fs.mkdir(path.dirname(destPath), { recursive: true });
  await fs.copyFile(srcPath, destPath);
}

const copiedDirFiles = [];
for (const [src, dest] of DIRECTORIES) {
  const srcPath = path.join(repoRoot, src);
  const destPath = path.join(resourcesRoot, dest);
  await fs.rm(destPath, { recursive: true, force: true });
  await fs.cp(srcPath, destPath, { recursive: true });
  for await (const entry of walk(srcPath)) {
    copiedDirFiles.push(path.join(src, path.relative(srcPath, entry)));
  }
}

async function* walk(dir) {
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(full);
    else yield full;
  }
}

const commit = execSync('git rev-parse HEAD', { cwd: repoRoot }).toString().trim();
const version = {
  syncedAt: new Date().toISOString(),
  sourceCommit: commit,
  files: [...FILES.map(([src]) => src), ...copiedDirFiles],
};
await fs.writeFile(
  path.join(resourcesRoot, 'content-version.json'),
  `${JSON.stringify(version, null, 2)}\n`,
  'utf8',
);

console.log(`Synced ${FILES.length + copiedDirFiles.length} files into ${path.relative(repoRoot, resourcesRoot)} at ${commit.slice(0, 7)}`);
