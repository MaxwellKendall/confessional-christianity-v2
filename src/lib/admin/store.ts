// Where /admin reads devotions from and writes them to. Devotions stay what
// they've always been — JSON files in content/devotions, reviewed as git
// commits — so there are two stores over the same files:
//
// - local: `next dev` on a checkout. Saves write straight to disk and
//   regenerate the manifest; the author commits like any other change.
// - github: the deployed admin (ADMIN_GITHUB_* set). Each devotion gets a
//   review branch, admin/devotions/<slug>; the first save opens a pull
//   request, later saves add commits to it. Merging is publishing — the
//   web goes live on the next deploy, iOS on its next content sync.
import { execFile } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { promisify } from 'node:util';

import type { Devotion } from '../devotions';
import { getAllDevotions } from '../devotions';
import type { DevotionSeries } from '../devotionSeries';
import { getAllSeries } from '../devotionSeries';
import {
  SLUG_PATTERN, relinkSeries, toContentJson, type SeriesLink,
} from '../devotionValidation';
import { createGitHubClient, githubConfig, type GitHubClient, type PullRequest } from './github';

export const DEVOTIONS_DIR = 'content/devotions';
export const SERIES_DIR = 'content/devotions/series';
export const REVIEW_BRANCH_PREFIX = 'admin/devotions/';

export const devotionPath = (slug: string) => `${DEVOTIONS_DIR}/${slug}.json`;
export const seriesPath = (slug: string) => `${SERIES_DIR}/${slug}.json`;

export interface AdminDevotionRow {
  devotion: Devotion;
  /** On the base branch (github) — false for a devotion that so far exists
   * only in its open pull request. Always true locally. */
  published: boolean;
  /** The open review PR carrying unmerged edits, if any. */
  pending: PullRequest | null;
}

export interface LoadedDevotion extends AdminDevotionRow {
  /** Every series as this devotion's branch sees them, for the part picker. */
  series: DevotionSeries[];
}

export type SaveResult =
  | { mode: 'local'; paths: string[] }
  | { mode: 'github'; paths: string[]; pullRequest: PullRequest; opened: boolean };

export interface SaveInput {
  devotion: Devotion;
  link: SeriesLink | null;
  isNew: boolean;
}

export interface DevotionStore {
  mode: 'local' | 'github';
  list(): Promise<AdminDevotionRow[]>;
  load(slug: string): Promise<LoadedDevotion | null>;
  /** Series as the base branch (or disk) has them — for a new devotion. */
  series(): Promise<DevotionSeries[]>;
  /** Every slug in the shared /devotions/[slug] namespace, drafts included. */
  takenSlugs(): Promise<string[]>;
  save(input: SaveInput): Promise<SaveResult>;
}

const bySlug = (a: { slug: string }, b: { slug: string }) => a.slug
  .localeCompare(b.slug, 'en', { numeric: true });

/** The files a save writes: the devotion plus any series whose parts it
 * moved, each laid out like its current text (toContentJson), and none
 * that would come out byte-identical. */
const filesToWrite = async (
  { devotion, link }: SaveInput,
  allSeries: DevotionSeries[],
  readText: (path: string) => Promise<string | null>,
): Promise<{ path: string; content: string }[]> => {
  const targets: [string, unknown][] = [
    [devotionPath(devotion.slug), devotion],
    ...relinkSeries(allSeries, devotion.slug, link).map((s): [string, unknown] => [seriesPath(s.slug), s]),
  ];
  const files = await Promise.all(targets.map(async ([filePath, value]) => {
    const original = await readText(filePath);
    const content = toContentJson(value, original);
    return content === original ? null : { path: filePath, content };
  }));
  const changed = files.filter((f): f is { path: string; content: string } => f !== null);
  if (!changed.length) throw new Error('Nothing to save: this already matches what is there.');
  return changed;
};

const commitMessage = ({ devotion, isNew }: SaveInput) => (
  `${isNew ? 'Add' : 'Update'} the "${devotion.title}" devotion (${devotion.slug})`
);

// ---------------------------------------------------------------------------
// local

const execFileAsync = promisify(execFile);

const createLocalStore = (root = process.cwd()): DevotionStore => {
  const readJsonDir = async <T>(dir: string): Promise<T[]> => {
    const names = (await fs.readdir(path.join(root, dir))).filter((n) => n.endsWith('.json'));
    return Promise.all(names.map(async (name) => JSON.parse(
      await fs.readFile(path.join(root, dir, name), 'utf8'),
    ) as T));
  };
  const readDevotions = async () => (await readJsonDir<Devotion>(DEVOTIONS_DIR)).sort(bySlug);
  const readSeries = async () => (await readJsonDir<DevotionSeries>(SERIES_DIR)).sort(bySlug);

  return {
    mode: 'local',
    async list() {
      return (await readDevotions()).map((devotion) => ({ devotion, published: true, pending: null }));
    },
    async load(slug) {
      const devotion = (await readDevotions()).find((d) => d.slug === slug);
      if (!devotion) return null;
      return { devotion, published: true, pending: null, series: await readSeries() };
    },
    series: readSeries,
    async takenSlugs() {
      return [...(await readDevotions()), ...(await readSeries())].map((x) => x.slug);
    },
    async save(input) {
      const files = await filesToWrite(input, await readSeries(), (filePath) => fs
        .readFile(path.join(root, filePath), 'utf8')
        .catch(() => null));
      await Promise.all(files.map((f) => fs.writeFile(path.join(root, f.path), f.content, 'utf8')));
      // a new file needs a manifest entry before the site can import it
      if (input.isNew) {
        await execFileAsync(process.execPath, [path.join(root, 'scripts/devotions/generate-manifest.mjs')], { cwd: root });
      }
      return { mode: 'local', paths: files.map((f) => f.path) };
    },
  };
};

// ---------------------------------------------------------------------------
// github

const reviewBranch = (slug: string) => `${REVIEW_BRANCH_PREFIX}${slug}`;

const prBody = (devotion: Devotion, paths: string[]) => [
  `Authored in /admin: **${devotion.title}** (\`${devotion.slug}\`).`,
  '',
  'Merging publishes it on the web with the next deploy. iOS picks it up on the next `npm run ios:sync-content` and app build.',
  '',
  'Files:',
  ...paths.map((p) => `- \`${p}\``),
].join('\n');

const createGitHubStore = (github: GitHubClient): DevotionStore => {
  const parse = <T>(text: string | null): T | null => (text ? JSON.parse(text) as T : null);

  const pendingBySlug = async (): Promise<Map<string, PullRequest>> => new Map(
    (await github.openPullRequests(REVIEW_BRANCH_PREFIX))
      .map((pr) => [pr.branch.slice(REVIEW_BRANCH_PREFIX.length), pr]),
  );

  /** Series as `ref` has them. Reads each manifest the deploy knows about
   * plus any the branch added, so a series authored by hand still shows. */
  const seriesAt = async (ref: string): Promise<DevotionSeries[]> => {
    const names = await github.listDirectory(SERIES_DIR, ref);
    const series = await Promise.all(names.filter((n) => n.endsWith('.json'))
      .map(async (name) => parse<DevotionSeries>(await github.readFile(`${SERIES_DIR}/${name}`, ref))));
    return series.filter((s): s is DevotionSeries => s !== null).sort(bySlug);
  };

  return {
    mode: 'github',
    async list() {
      // published = what this deployment was built from; one API call for
      // the open PRs, plus one read per devotion that has unmerged edits
      const pending = await pendingBySlug();
      const published = getAllDevotions();
      const rows: AdminDevotionRow[] = published.map((devotion) => ({
        devotion, published: true, pending: pending.get(devotion.slug) ?? null,
      }));
      await Promise.all([...pending].map(async ([slug, pr]) => {
        const draft = parse<Devotion>(await github.readFile(devotionPath(slug), pr.branch));
        if (!draft) return;
        const row = rows.find((r) => r.devotion.slug === slug);
        if (row) row.devotion = draft;
        else rows.push({ devotion: draft, published: false, pending: pr });
      }));
      return rows.sort((a, b) => bySlug(a.devotion, b.devotion));
    },
    async load(slug) {
      // slugs become repository paths below; refuse anything else up front
      if (!SLUG_PATTERN.test(slug)) return null;
      const pr = (await pendingBySlug()).get(slug) ?? null;
      const ref = pr?.branch ?? github.config.baseBranch;
      const devotion = parse<Devotion>(await github.readFile(devotionPath(slug), ref));
      if (!devotion) return null;
      const published = pr
        ? (await github.readFile(devotionPath(slug))) !== null
        : true;
      return { devotion, published, pending: pr, series: await seriesAt(ref) };
    },
    series: () => seriesAt(github.config.baseBranch),
    async takenSlugs() {
      const [devotions, series, pending] = await Promise.all([
        github.listDirectory(DEVOTIONS_DIR),
        github.listDirectory(SERIES_DIR),
        pendingBySlug(),
      ]);
      return [
        ...[...devotions, ...series].filter((n) => n.endsWith('.json')).map((n) => n.slice(0, -5)),
        ...getAllDevotions().map((d) => d.slug),
        ...getAllSeries().map((s) => s.slug),
        ...pending.keys(),
      ];
    },
    async save(input) {
      const { devotion } = input;
      const branch = reviewBranch(devotion.slug);
      const existing = (await pendingBySlug()).get(devotion.slug) ?? null;
      // build on the commit's parent — the open PR's branch, else the base —
      // so a second save on an open PR relinks against its own first save
      const ref = existing ? branch : github.config.baseBranch;
      const files = await filesToWrite(input, await seriesAt(ref), (filePath) => github.readFile(filePath, ref));
      await github.commitFiles(branch, files, commitMessage(input), { restart: !existing });
      const paths = files.map((f) => f.path);
      if (existing) return { mode: 'github', paths, pullRequest: existing, opened: false };
      const pullRequest = await github.openPullRequest(
        branch,
        `${input.isNew ? 'New devotion' : 'Edit devotion'}: ${devotion.title}`,
        prBody(devotion, paths),
      );
      return { mode: 'github', paths, pullRequest, opened: true };
    },
  };
};

// ---------------------------------------------------------------------------

export type StoreSetup =
  | { ok: true; store: DevotionStore }
  | { ok: false; reason: string };

/** GitHub when it's configured; the working tree under `next dev`; nothing
 * otherwise — a deployed admin without a token has nowhere safe to write. */
export const getDevotionStore = (): StoreSetup => {
  const config = githubConfig();
  if (config) return { ok: true, store: createGitHubStore(createGitHubClient(config)) };
  if (process.env.NODE_ENV === 'development') return { ok: true, store: createLocalStore() };
  return {
    ok: false,
    reason: 'Saving is not configured. Set ADMIN_GITHUB_TOKEN and ADMIN_GITHUB_REPO so saves open pull requests.',
  };
};

export { createLocalStore as _createLocalStoreForTests };
