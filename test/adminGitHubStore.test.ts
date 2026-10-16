// The deployed admin's save path against a fake GitHub: the first save of a
// devotion opens a review PR from admin/devotions/<slug>; later saves add
// commits to that same PR, relinking series against the branch's own state.
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { getDevotionStore } from '@/lib/admin/store';
import { getDevotion } from '@/lib/devotions';
import type { Devotion } from '@/lib/devotions';

const root = path.resolve(__dirname, '..');

interface Commit { parent: string | null; files: Record<string, string> }

const fakeGitHub = () => {
  const commits: Record<string, Commit> = { base: { parent: null, files: {} } };
  const refs: Record<string, string> = { main: 'base' };
  const pulls: { number: number; html_url: string; head: { ref: string; repo: { full_name: string } } }[] = [];
  const trees: Record<string, { parent: string; files: Record<string, string> }> = {};
  const calls: string[] = [];
  let seq = 0;

  const fileAt = (sha: string, file: string): string | null => {
    for (let c: string | null = sha; c; c = commits[c].parent) {
      if (file in commits[c].files) return commits[c].files[file];
    }
    try {
      return readFileSync(path.join(root, file), 'utf8');
    } catch {
      return null;
    }
  };

  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status });

  const fetchMock = vi.fn(async (url: string, init: RequestInit = {}) => {
    const method = init.method ?? 'GET';
    const u = new URL(url);
    const p = decodeURIComponent(u.pathname.replace('/repos/owner/repo', ''));
    const body = init.body ? JSON.parse(String(init.body)) : null;
    calls.push(`${method} ${p}`);

    if (method === 'GET' && p === '/pulls') return json(pulls);
    if (method === 'GET' && p.startsWith('/contents/')) {
      const file = p.slice('/contents/'.length);
      const sha = refs[u.searchParams.get('ref') ?? 'main'];
      if (!sha) return json({}, 404);
      if (!file.endsWith('.json')) {
        const names = new Set(readdirSync(path.join(root, file)).filter((n) => n.endsWith('.json')));
        for (let c: string | null = sha; c; c = commits[c].parent) {
          Object.keys(commits[c].files).filter((f) => path.dirname(f) === file).forEach((f) => names.add(path.basename(f)));
        }
        return json([...names].map((name) => ({ name, type: 'file' })));
      }
      const content = fileAt(sha, file);
      return content === null ? json({}, 404) : json({ content: Buffer.from(content).toString('base64'), encoding: 'base64' });
    }
    if (method === 'GET' && p.startsWith('/git/ref/heads/')) {
      const sha = refs[p.slice('/git/ref/heads/'.length)];
      return sha ? json({ object: { sha } }) : json({}, 404);
    }
    if (method === 'GET' && p.startsWith('/git/commits/')) return json({ tree: { sha: `tree-of-${p.slice(13)}` } });
    if (method === 'POST' && p === '/git/trees') {
      const sha = `tree${(seq += 1)}`;
      trees[sha] = {
        parent: body.base_tree.replace('tree-of-', ''),
        files: Object.fromEntries(body.tree.map((t: { path: string; content: string }) => [t.path, t.content])),
      };
      return json({ sha });
    }
    if (method === 'POST' && p === '/git/commits') {
      const sha = `commit${(seq += 1)}`;
      expect(trees[body.tree].parent).toBe(body.parents[0]);
      commits[sha] = { parent: body.parents[0], files: trees[body.tree].files };
      return json({ sha });
    }
    if (method === 'POST' && p === '/git/refs') {
      refs[body.ref.replace('refs/heads/', '')] = body.sha;
      return json({}, 201);
    }
    if (method === 'PATCH' && p.startsWith('/git/refs/heads/')) {
      refs[p.slice('/git/refs/heads/'.length)] = body.sha;
      return json({});
    }
    if (method === 'POST' && p === '/pulls') {
      const pr = { number: 40 + pulls.length, html_url: `https://github.com/owner/repo/pull/${40 + pulls.length}`, head: { ref: body.head, repo: { full_name: 'owner/repo' } } };
      pulls.push(pr);
      return json(pr, 201);
    }
    throw new Error(`unexpected ${method} ${p}`);
  });

  return { fetchMock, refs, pulls, calls, fileAt };
};

const advent4 = (): Devotion => ({
  ...structuredClone(getDevotion('advent-3')!),
  slug: 'advent-4',
  title: 'A Prophet Like Moses',
  grounding: { kind: 'season', season: 'advent', day: 4 },
});

describe('the GitHub-backed store', () => {
  let gh: ReturnType<typeof fakeGitHub>;

  beforeEach(() => {
    gh = fakeGitHub();
    vi.stubGlobal('fetch', gh.fetchMock);
    vi.stubEnv('ADMIN_GITHUB_TOKEN', 'token');
    vi.stubEnv('ADMIN_GITHUB_REPO', 'owner/repo');
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  const store = () => {
    const setup = getDevotionStore();
    if (!setup.ok) throw new Error(setup.reason);
    expect(setup.store.mode).toBe('github');
    return setup.store;
  };

  test('the first save opens a PR with the devotion and its series part', async () => {
    const result = await store().save({ devotion: advent4(), link: { seriesSlug: 'advent', day: 4 }, isNew: true });

    expect(result).toMatchObject({ mode: 'github', opened: true, pullRequest: { number: 40, branch: 'admin/devotions/advent-4' } });
    expect(result.paths).toEqual(['content/devotions/advent-4.json', 'content/devotions/series/advent.json']);
    const branch = gh.refs['admin/devotions/advent-4'];
    expect(JSON.parse(gh.fileAt(branch, 'content/devotions/advent-4.json')!).title).toBe('A Prophet Like Moses');
    expect(JSON.parse(gh.fileAt(branch, 'content/devotions/series/advent.json')!).parts[3].devotionSlug).toBe('advent-4');
    expect(gh.refs.main).toBe('base');
  });

  test('later saves add commits to the open PR and show up as drafts', async () => {
    const s = store();
    await s.save({ devotion: advent4(), link: { seriesSlug: 'advent', day: 4 }, isNew: true });
    const first = gh.refs['admin/devotions/advent-4'];

    const edited = { ...advent4(), summary: 'Revised.' };
    const again = await s.save({ devotion: edited, link: { seriesSlug: 'advent', day: 4 }, isNew: false });
    expect(again).toMatchObject({ opened: false, pullRequest: { number: 40 } });
    // the series already links advent-4 on the branch, so only the devotion changes
    expect(again.paths).toEqual(['content/devotions/advent-4.json']);
    expect(gh.pulls).toHaveLength(1);
    expect(gh.calls).toContain(`GET /git/commits/${first}`);

    const loaded = await s.load('advent-4');
    expect(loaded).toMatchObject({ published: false, pending: { number: 40 }, devotion: { summary: 'Revised.' } });
    expect(loaded!.series.find((x) => x.slug === 'advent')!.parts[3].devotionSlug).toBe('advent-4');

    const row = (await s.list()).find((r) => r.devotion.slug === 'advent-4');
    expect(row).toMatchObject({ published: false, pending: { number: 40 } });
    expect(await s.takenSlugs()).toContain('advent-4');
  });

  test('a save that changes nothing is refused rather than committed', async () => {
    const psalm = structuredClone(getDevotion('advent-3')!);
    await expect(store().save({ devotion: psalm, link: { seriesSlug: 'advent', day: 3 }, isNew: false }))
      .rejects.toThrow(/Nothing to save/);
    expect(gh.calls.filter((c) => c.startsWith('POST'))).toEqual([]);
  });

  test('editing a published devotion reads it from the base branch', async () => {
    const loaded = await store().load('psalm-130');
    expect(loaded).toMatchObject({ published: true, pending: null, devotion: { slug: 'psalm-130' } });
    expect(await store().load('no-such-devotion')).toBeNull();
    expect(await store().load('../../package')).toBeNull();
  });
});

describe('store selection', () => {
  afterEach(() => vi.unstubAllEnvs());

  test('a deployment without GitHub configured has nowhere to save', () => {
    vi.stubEnv('ADMIN_GITHUB_TOKEN', '');
    vi.stubEnv('NODE_ENV', 'production');
    expect(getDevotionStore()).toMatchObject({ ok: false });
  });

  test('next dev saves to the working tree', () => {
    vi.stubEnv('ADMIN_GITHUB_TOKEN', '');
    vi.stubEnv('NODE_ENV', 'development');
    expect(getDevotionStore()).toMatchObject({ ok: true, store: { mode: 'local' } });
  });
});
