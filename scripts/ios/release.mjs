#!/usr/bin/env node
// TKL-814: archive the iOS app and upload it to TestFlight, then wait for processing.
//
//   npm run ios:release -- --dry-run                 archive + export an .ipa locally; nothing uploaded, no file changed
//   npm run ios:release                              bump the build number, archive, upload, wait until VALID
//   npm run ios:release -- --marketing-version 1.2   also set MARKETING_VERSION
//
// The App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH in ~/dev/.secrets.env) is
// used only to read builds; it is never printed. Signing and the upload go through the Xcode account
// on this Mac (TKL-880). This script never submits for review and never releases a version.
import { spawn } from 'node:child_process';
import { createSign } from 'node:crypto';
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  APP_ID,
  archiveArgs,
  exportArgs,
  exportPlist,
  highestBuildNumber,
  parseArgs,
  processingVerdict,
  readVersions,
  redact,
  setVersions,
  usage,
} from './release-lib.mjs';

const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const appDir = join(root, 'ios/App');
const projectYmlPath = join(appDir, 'project.yml');
const outDir = join(root, 'build/release');
const POLL_EVERY_MS = 30_000;
const POLL_FOR_MS = 45 * 60_000;

let secrets = [];
const say = (line = '') => console.log(redact(line, secrets));

function loadSecrets(path = join(homedir(), 'dev/.secrets.env')) {
  if (!existsSync(path)) return;
  for (const raw of readFileSync(path, 'utf8').split('\n')) {
    const line = raw.trim().replace(/^export\s+/, '');
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (/^(['"]).*\1$/.test(value)) value = value.slice(1, -1);
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

function ascAuth() {
  const { ASC_KEY_ID: keyId, ASC_ISSUER_ID: issuerId } = process.env;
  const keyPath = (process.env.ASC_KEY_PATH || '').replace(/^~(?=\/)/, homedir());
  if (!keyId || !issuerId || !keyPath) throw new Error('ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH must be set (~/dev/.secrets.env).');
  if (!existsSync(keyPath)) throw new Error('ASC_KEY_PATH does not point at a file.');
  secrets = [keyId, issuerId];
  return { keyId, issuerId, keyPath };
}

function jwt({ keyId, issuerId, keyPath }) {
  const b64 = (v) => Buffer.from(v).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const data = `${b64(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))}.${b64(JSON.stringify({ iss: issuerId, iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' }))}`;
  const sig = createSign('SHA256').update(data).sign({ key: readFileSync(keyPath), dsaEncoding: 'ieee-p1363' });
  return `${data}.${b64(sig)}`;
}

/** Read-only App Store Connect client: GET is the only method this script ever sends. */
async function ascGet(auth, pathOrUrl, attempt = 0) {
  const url = pathOrUrl.startsWith('http') ? pathOrUrl : `https://api.appstoreconnect.apple.com${pathOrUrl}`;
  const res = await fetch(url, { method: 'GET', headers: { Authorization: `Bearer ${jwt(auth)}` } });
  if (!res.ok) {
    if ((res.status === 429 || res.status >= 500) && attempt < 4) {
      await new Promise((r) => setTimeout(r, 2 ** attempt * 1000));
      return ascGet(auth, pathOrUrl, attempt + 1);
    }
    throw new Error(`App Store Connect GET ${new URL(url).pathname} failed: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`);
  }
  return res.json();
}

async function allBuilds(auth) {
  const builds = [];
  let next = `/v1/builds?filter[app]=${APP_ID}&limit=200&fields[builds]=version,processingState,expired,uploadedDate`;
  while (next) {
    const page = await ascGet(auth, next);
    builds.push(...(page.data || []));
    next = page.links?.next;
  }
  return builds;
}

function run(command, args, { cwd = root, log } = {}) {
  return new Promise((resolvePromise) => {
    const child = spawn(command, args, { cwd, env: process.env });
    const file = log ? createWriteStream(log) : null;
    let tail = '';
    const take = (chunk) => {
      file?.write(chunk);
      tail = (tail + chunk.toString()).slice(-4000);
    };
    child.stdout.on('data', take);
    child.stderr.on('data', take);
    child.on('error', (error) => { take(String(error)); });
    child.on('close', (code) => { file?.end(); resolvePromise({ code: code ?? 1, tail }); });
  });
}

async function step(label, command, args, opts) {
  const started = Date.now();
  say(`- ${label}…`);
  const { code, tail } = await run(command, args, opts);
  const secs = Math.round((Date.now() - started) / 1000);
  if (code !== 0) {
    say(tail.split('\n').slice(-25).join('\n'));
    throw new Error(`${label} failed (exit ${code}, ${secs}s)${opts?.log ? `; full log: ${opts.log}` : ''}`);
  }
  say(`  ok (${secs}s)`);
  return tail;
}

async function waitForProcessing(auth, build, marketing) {
  const deadline = Date.now() + POLL_FOR_MS;
  let last = '';
  while (Date.now() < deadline) {
    const found = await ascGet(auth, `/v1/builds?filter[app]=${APP_ID}&filter[version]=${build}&filter[preReleaseVersion.version]=${encodeURIComponent(marketing)}&limit=5`);
    const row = found.data?.[0];
    const verdict = processingVerdict(row);
    const state = row?.attributes?.processingState ?? 'NOT_LISTED_YET';
    if (state !== last) { say(`  build ${build}: ${state}`); last = state; }
    if (verdict === 'valid') return row;
    if (verdict === 'failed') throw new Error(`Build ${build} processing ended ${state}.`);
    await new Promise((r) => setTimeout(r, POLL_EVERY_MS));
  }
  throw new Error(`Build ${build} was still not VALID after ${POLL_FOR_MS / 60_000} minutes; check App Store Connect.`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { say(usage()); return; }
  loadSecrets();
  const auth = ascAuth();

  const originalYml = readFileSync(projectYmlPath, 'utf8');
  const local = readVersions(originalYml);
  const builds = await allBuilds(auth);
  const highest = highestBuildNumber(builds);
  const build = Math.max(Number(local.build), highest) + 1;
  const marketing = args.marketingVersion ?? local.marketing;

  say(args.dryRun ? 'iOS release: DRY RUN (archive + local export; no upload, project.yml untouched)' : 'iOS release: archive and upload to TestFlight');
  say(`- project.yml: ${local.marketing} (${local.build}); App Store Connect highest build: ${highest} of ${builds.length}`);
  say(`- this build: ${marketing} (${build})`);

  if (!args.dryRun) writeFileSync(projectYmlPath, setVersions(originalYml, { build, marketing }));

  rmSync(outDir, { recursive: true, force: true });
  mkdirSync(outDir, { recursive: true });
  const archivePath = join(outDir, 'ConfessionalChristianity.xcarchive');
  const exportPath = join(outDir, 'export');
  const plistPath = join(outDir, 'ExportOptions.plist');
  writeFileSync(plistPath, exportPlist({ upload: !args.dryRun }));

  try {
    await step('xcodegen generate', 'xcodegen', ['generate', '--quiet'], { cwd: appDir });
    await step('xcodebuild archive', 'xcodebuild',
      archiveArgs({ archivePath, overrides: args.dryRun ? { build, marketing } : undefined }),
      { cwd: appDir, log: join(outDir, 'archive.log') });
  } catch (error) {
    if (!args.dryRun) {
      // Nothing was uploaded, so the build number is not used up: put project.yml back.
      writeFileSync(projectYmlPath, originalYml);
      await run('xcodegen', ['generate', '--quiet'], { cwd: appDir });
      say('- restored project.yml (nothing was uploaded)');
    }
    throw error;
  }

  await step(args.dryRun ? 'xcodebuild -exportArchive (local .ipa)' : 'xcodebuild -exportArchive (upload to App Store Connect)',
    'xcodebuild', exportArgs({ archivePath, exportPath, plistPath }), { cwd: appDir, log: join(outDir, 'export.log') });

  if (args.dryRun) {
    const ipa = join(exportPath, 'ConfessionalChristianity.ipa');
    const size = existsSync(ipa) ? `${(statSync(ipa).size / 1e6).toFixed(1)} MB` : 'missing';
    say(`- exported ${ipa} (${size})`);
    say(`RESULT dry-run build=${build} marketing=${marketing} uploaded=no`);
    say('Nothing was uploaded, submitted or released.');
    return;
  }

  say('- waiting for App Store Connect processing');
  await waitForProcessing(auth, build, marketing);
  say(`RESULT build=${build} marketing=${marketing} uploaded=yes state=VALID`);
  say('Not submitted for review and not released. Commit and push ios/App/project.yml and the regenerated project.pbxproj.');
}

main().catch((error) => {
  console.error(redact(`ios-release: ${error.message}`, secrets));
  process.exit(1);
});
