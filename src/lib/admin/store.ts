// Where /admin reads devotions and series from and writes them to. Both stay
// what they've always been — JSON files under content/devotions, reviewed as
// git commits — so there are two stores over the same files:
//
// - local: `next dev` on a checkout. Saves write straight to disk and
//   regenerate the manifest; the author commits like any other change.
// - github: the deployed admin (ADMIN_GITHUB_* set). Each devotion or series
//   gets a review branch (admin/devotions/<slug>, admin/series/<slug>); the
//   first save opens a pull request, later saves add commits to it. Merging
//   is publishing — the web goes live on the next deploy, iOS on its next
//   content sync.
import { execFile } from 'node:child_process';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { promisify } from 'node:util';

import type { Devotion } from '../devotions';
import { getAllDevotions } from '../devotions';
import type { DevotionSeries } from '../devotionSeries';
import { getAllSeries } from '../devotionSeries';
import {
  SLUG_PATTERN, mergeSeriesEdit, relinkSeries, toContentJson, type SeriesLink,
} from '../devotionValidation';
import { createGitHubClient, githubConfig, type GitHubClient, type PullRequest } from './github';

export const DEVOTIONS_DIR = 'content/devotions';
export const SERIES_DIR = 'content/devotions/series';
export const REVIEW_BRANCH_PREFIX = 'admin/devotions/';
export const SERIES_BRANCH_PREFIX = 'admin/series/';
export const FEATURED_BRANCH = 'admin/featured';
export const FEATURED_PATH = 'content/featured-devotion.json';

export const devotionPath = (slug: string) => `${DEVOTIONS_DIR}/${slug}.json`;
export const seriesPath = (slug: string) => `${SERIES_DIR}/${slug}.json`;

interface ReviewState {
  /** On the base branch (github) — false for something that so far exists
   * only in its open pull request. Always true locally. */
  published: boolean;
  /** The open review PR carrying unmerged edits, if any. */
  pending: PullRequest | null;
}

export interface AdminDevotionRow extends ReviewState {
  devotion: Devotion;
}

export interface LoadedDevotion extends AdminDevotionRow {
  /** Every series as this devotion's branch sees them, for the part picker. */
  series: DevotionSeries[];
}

export interface AdminSeriesRow extends ReviewState {
  series: DevotionSeries;
}

export interface LoadedSeries extends AdminSeriesRow {
  /** How many leading parts households already have — fixed in place, since
   * progress is stored by day number. 0 for a series not yet published. */
  lockedParts: number;
  /** Every other series, for the one-series-per-source check. */
  otherSeries: DevotionSeries[];
}

export type SaveResult =
  | { mode: 'local'; paths: string[] }
  | { mode: 'github'; paths: string[]; pullRequest: PullRequest; opened: boolean };

export interface SaveInput {
  devotion: Devotion;
  link: SeriesLink | null;
  isNew: boolean;
}

export interface SeriesSaveInput {
  series: DevotionSeries;
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
  listSeries(): Promise<AdminSeriesRow[]>;
  loadSeries(slug: string): Promise<LoadedSeries | null>;
  saveSeries(input: SeriesSaveInput): Promise<SaveResult>;
  /** The hub's featured devotion, and the open PR changing it, if any. */
  featured(): Promise<{ slug: string; pending: PullRequest | null }>;
  setFeatured(slug: string): Promise<SaveResult>;
  /** Closes a draft's review PR and deletes its branch (github only). */
  discard(kind: 'devotion' | 'series', slug: string): Promise<void>;
}

const NO_DRAFTS = 'Drafts only exist when saves open pull requests; locally, discard changes with git.';

type FileWrite = { path: string; content: string };

const bySlug = (a: { slug: string }, b: { slug: string }) => a.slug
  .localeCompare(b.slug, 'en', { numeric: true });

/** Lays each value out like its file's current text (toContentJson) and
 * drops the ones that would come out byte-identical. */
const changedFiles = async (
  targets: [string, unknown][],
  readText: (path: string) => Promise<string | null>,
): Promise<FileWrite[]> => {
  const files = await Promise.all(targets.map(async ([filePath, value]) => {
    const original = await readText(filePath);
    const content = toContentJson(value, original);
    return content === original ? null : { path: filePath, content };
  }));
  const changed = files.filter((f): f is FileWrite => f !== null);
  if (!changed.length) throw new Error('Nothing to save: this already matches what is there.');
  return changed;
};

/** A devotion save writes the devotion plus any series whose parts it moved. */
const devotionFiles = (
  { devotion, link }: SaveInput,
  allSeries: DevotionSeries[],
  readText: (path: string) => Promise<string | null>,
) => changedFiles([
  [devotionPath(devotion.slug), devotion],
  ...relinkSeries(allSeries, devotion.slug, link).map((s): [string, unknown] => [seriesPath(s.slug), s]),
], readText);

/** A series save writes only its own manifest, with devotion links and
 * published parts kept as mergeSeriesEdit rules. */
const seriesFiles = (
  { series }: SeriesSaveInput,
  current: DevotionSeries | null,
  published: DevotionSeries | null,
  readText: (path: string) => Promise<string | null>,
) => changedFiles([[seriesPath(series.slug), mergeSeriesEdit(series, current, published)]], readText);

const commitMessage = ({ devotion, isNew }: SaveInput) => (
  `${isNew ? 'Add' : 'Update'} the "${devotion.title}" devotion (${devotion.slug})`
);

const seriesCommitMessage = ({ series, isNew }: SeriesSaveInput) => (
  `${isNew ? 'Add' : 'Update'} the "${series.title}" devotion series (${series.slug})`
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
  const readText = (filePath: string) => fs.readFile(path.join(root, filePath), 'utf8').catch(() => null);
  /** The committed version — the closest a checkout has to "published". */
  const readCommittedSeries = (slug: string): Promise<DevotionSeries | null> => execFileAsync(
    'git', ['show', `HEAD:${seriesPath(slug)}`], { cwd: root },
  ).then(({ stdout }) => JSON.parse(stdout) as DevotionSeries).catch(() => null);

  const write = async (files: FileWrite[], isNew: boolean): Promise<SaveResult> => {
    await Promise.all(files.map((f) => fs.writeFile(path.join(root, f.path), f.content, 'utf8')));
    // a new file needs a manifest entry before the site can import it
    if (isNew) {
      await execFileAsync(process.execPath, [path.join(root, 'scripts/devotions/generate-manifest.mjs')], { cwd: root });
    }
    return { mode: 'local', paths: files.map((f) => f.path) };
  };

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
      return write(await devotionFiles(input, await readSeries(), readText), input.isNew);
    },
    async listSeries() {
      return (await readSeries()).map((series) => ({ series, published: true, pending: null }));
    },
    async loadSeries(slug) {
      const all = await readSeries();
      const series = all.find((s) => s.slug === slug);
      if (!series) return null;
      const committed = await readCommittedSeries(slug);
      return {
        series, published: committed !== null, pending: null, lockedParts: committed?.parts.length ?? 0,
        otherSeries: all.filter((s) => s.slug !== slug),
      };
    },
    async saveSeries(input) {
      const current = (await readSeries()).find((s) => s.slug === input.series.slug) ?? null;
      const committed = await readCommittedSeries(input.series.slug);
      return write(await seriesFiles(input, current, committed, readText), input.isNew);
    },
    async featured() {
      const text = await readText(FEATURED_PATH);
      return { slug: text ? (JSON.parse(text) as { slug: string }).slug : '', pending: null };
    },
    async setFeatured(slug) {
      if (!SLUG_PATTERN.test(slug) || (await readText(devotionPath(slug))) === null) {
        throw new Error(`there is no devotion "${slug}" to feature`);
      }
      return write(await changedFiles([[FEATURED_PATH, { slug }]], readText), false);
    },
    async discard() {
      throw new Error(NO_DRAFTS);
    },
  };
};

// ---------------------------------------------------------------------------
// github

const prBody = (what: string, paths: string[]) => [
  `Authored in /admin: ${what}.`,
  '',
  'Merging publishes it on the web with the next deploy. iOS picks it up on the next `npm run ios:sync-content` and app build.',
  '',
  'Files:',
  ...paths.map((p) => `- \`${p}\``),
].join('\n');

const createGitHubStore = (github: GitHubClient): DevotionStore => {
  const base = github.config.baseBranch;
  const parse = <T>(text: string | null): T | null => (text ? JSON.parse(text) as T : null);

  const pendingBySlug = async (prefix: string): Promise<Map<string, PullRequest>> => new Map(
    (await github.openPullRequests(prefix)).map((pr) => [pr.branch.slice(prefix.length), pr]),
  );

  /** Series as `ref` has them — every manifest in the directory, so one
   * added by hand or on the branch shows too. */
  const seriesAt = async (ref: string): Promise<DevotionSeries[]> => {
    const names = await github.listDirectory(SERIES_DIR, ref);
    const series = await Promise.all(names.filter((n) => n.endsWith('.json'))
      .map(async (name) => parse<DevotionSeries>(await github.readFile(`${SERIES_DIR}/${name}`, ref))));
    return series.filter((s): s is DevotionSeries => s !== null).sort(bySlug);
  };

  /** Commits to `<prefix><slug>`, opening its PR on the first save. */
  const commitForReview = async (
    branch: string,
    existing: PullRequest | null,
    files: FileWrite[],
    message: string,
    prTitle: string,
    what: string,
  ): Promise<SaveResult> => {
    await github.commitFiles(branch, files, message, { restart: !existing });
    const paths = files.map((f) => f.path);
    if (existing) return { mode: 'github', paths, pullRequest: existing, opened: false };
    const pullRequest = await github.openPullRequest(branch, prTitle, prBody(what, paths));
    return { mode: 'github', paths, pullRequest, opened: true };
  };

  return {
    mode: 'github',
    async list() {
      // published = what this deployment was built from; one API call for
      // the open PRs, plus one read per devotion that has unmerged edits
      const pending = await pendingBySlug(REVIEW_BRANCH_PREFIX);
      const rows: AdminDevotionRow[] = getAllDevotions().map((devotion) => ({
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
      const pr = (await pendingBySlug(REVIEW_BRANCH_PREFIX)).get(slug) ?? null;
      const ref = pr?.branch ?? base;
      const devotion = parse<Devotion>(await github.readFile(devotionPath(slug), ref));
      if (!devotion) return null;
      const published = pr ? (await github.readFile(devotionPath(slug))) !== null : true;
      return { devotion, published, pending: pr, series: await seriesAt(ref) };
    },
    series: () => seriesAt(base),
    async takenSlugs() {
      const [devotions, series, pendingDevotions, pendingSeries] = await Promise.all([
        github.listDirectory(DEVOTIONS_DIR),
        github.listDirectory(SERIES_DIR),
        pendingBySlug(REVIEW_BRANCH_PREFIX),
        pendingBySlug(SERIES_BRANCH_PREFIX),
      ]);
      return [
        ...[...devotions, ...series].filter((n) => n.endsWith('.json')).map((n) => n.slice(0, -5)),
        ...getAllDevotions().map((d) => d.slug),
        ...getAllSeries().map((s) => s.slug),
        ...pendingDevotions.keys(),
        ...pendingSeries.keys(),
      ];
    },
    async save(input) {
      const { devotion } = input;
      const branch = `${REVIEW_BRANCH_PREFIX}${devotion.slug}`;
      const existing = (await pendingBySlug(REVIEW_BRANCH_PREFIX)).get(devotion.slug) ?? null;
      // build on the commit's parent — the open PR's branch, else the base —
      // so a second save on an open PR relinks against its own first save
      const ref = existing ? branch : base;
      const files = await devotionFiles(input, await seriesAt(ref), (p) => github.readFile(p, ref));
      return commitForReview(
        branch, existing, files, commitMessage(input),
        `${input.isNew ? 'New devotion' : 'Edit devotion'}: ${devotion.title}`,
        `**${devotion.title}** (\`${devotion.slug}\`)`,
      );
    },
    async listSeries() {
      const pending = await pendingBySlug(SERIES_BRANCH_PREFIX);
      const rows: AdminSeriesRow[] = (await seriesAt(base)).map((series) => ({
        series, published: true, pending: pending.get(series.slug) ?? null,
      }));
      await Promise.all([...pending].map(async ([slug, pr]) => {
        const draft = parse<DevotionSeries>(await github.readFile(seriesPath(slug), pr.branch));
        if (!draft) return;
        const row = rows.find((r) => r.series.slug === slug);
        if (row) row.series = draft;
        else rows.push({ series: draft, published: false, pending: pr });
      }));
      return rows.sort((a, b) => bySlug(a.series, b.series));
    },
    async loadSeries(slug) {
      if (!SLUG_PATTERN.test(slug)) return null;
      const pr = (await pendingBySlug(SERIES_BRANCH_PREFIX)).get(slug) ?? null;
      const [draft, published, others] = await Promise.all([
        pr ? github.readFile(seriesPath(slug), pr.branch).then((t) => parse<DevotionSeries>(t)) : null,
        github.readFile(seriesPath(slug)).then((t) => parse<DevotionSeries>(t)),
        seriesAt(base),
      ]);
      const series = draft ?? published;
      if (!series) return null;
      return {
        series,
        published: published !== null,
        pending: pr,
        lockedParts: published?.parts.length ?? 0,
        otherSeries: others.filter((s) => s.slug !== slug),
      };
    },
    async saveSeries(input) {
      const { series } = input;
      const branch = `${SERIES_BRANCH_PREFIX}${series.slug}`;
      const existing = (await pendingBySlug(SERIES_BRANCH_PREFIX)).get(series.slug) ?? null;
      const ref = existing ? branch : base;
      const [current, published] = await Promise.all([
        github.readFile(seriesPath(series.slug), ref).then((t) => parse<DevotionSeries>(t)),
        github.readFile(seriesPath(series.slug)).then((t) => parse<DevotionSeries>(t)),
      ]);
      // a devotion PR may have linked a part on the base since this branch
      // was cut; take links from the base too so this save can't drop them
      const linksFrom = current && published
        ? { ...current, parts: current.parts.map((p) => ({ ...p, devotionSlug: p.devotionSlug ?? published.parts.find((q) => q.day === p.day)?.devotionSlug })) }
        : current ?? published;
      const files = await seriesFiles(input, linksFrom, published, (p) => github.readFile(p, ref));
      return commitForReview(
        branch, existing, files, seriesCommitMessage(input),
        `${input.isNew ? 'New devotion series' : 'Edit devotion series'}: ${series.title}`,
        `the **${series.title}** series (\`${series.slug}\`)`,
      );
    },
    async featured() {
      const pending = (await github.openPullRequests(FEATURED_BRANCH)).find((pr) => pr.branch === FEATURED_BRANCH) ?? null;
      const featured = parse<{ slug: string }>(await github.readFile(FEATURED_PATH, pending?.branch ?? base));
      return { slug: featured?.slug ?? '', pending };
    },
    async setFeatured(slug) {
      // only a published devotion: the hub can't feature one still in review
      if (!SLUG_PATTERN.test(slug) || (await github.readFile(devotionPath(slug))) === null) {
        throw new Error(`"${slug}" isn't published yet, so it can't be featured`);
      }
      const existing = (await github.openPullRequests(FEATURED_BRANCH)).find((pr) => pr.branch === FEATURED_BRANCH) ?? null;
      const ref = existing ? FEATURED_BRANCH : base;
      const files = await changedFiles([[FEATURED_PATH, { slug }]], (p) => github.readFile(p, ref));
      const title = getAllDevotions().find((d) => d.slug === slug)?.title ?? slug;
      return commitForReview(
        FEATURED_BRANCH, existing, files, `Feature the "${title}" devotion (${slug})`,
        `Featured devotion: ${title}`, `**${title}** (\`${slug}\`) as the featured devotion`,
      );
    },
    async discard(kind, slug) {
      const prefix = kind === 'devotion' ? REVIEW_BRANCH_PREFIX : SERIES_BRANCH_PREFIX;
      const pr = (await pendingBySlug(prefix)).get(slug);
      if (!pr) throw new Error(`there is no draft of "${slug}" to discard`);
      await github.discardPullRequest(pr);
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
