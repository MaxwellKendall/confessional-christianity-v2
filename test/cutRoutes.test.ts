// TKL-856 cut devotions, reading plans, Family Worship and the web /programs
// session. Every one of those routes was in the sitemap, so each must 301 to
// its nearest surviving page instead of 404ing, and none may stay listed.
import { describe, expect, test } from 'vitest';

import nextConfig from '../next.config';
import sitemap from '@/app/sitemap';

type Redirect = { source: string; destination: string; statusCode?: number };

// Just enough of Next's path matching for these rules: `:p(a|b)`, `:p*`, `:p`.
const toRegExp = (source: string) => new RegExp(`^${source.replace(
  /\/:\w+\*|:\w+\(([^)]+)\)|:\w+/g,
  (token, alternatives?: string) => (token.endsWith('*') ? '(?:/.*)?'
    : alternatives ? `(?:${alternatives})` : '[^/]+'),
)}$`);

const resolve = async (path: string) => {
  const rules = (await nextConfig.redirects!()) as Redirect[];
  return rules.find((r) => toRegExp(r.source).test(path)) ?? null;
};

describe('cut routes redirect permanently', () => {
  const cases: Array<[string, string]> = [
    ['/devotions', '/'],
    ['/devotions/advent', '/'],
    ['/devotions/wsc-1/worship', '/'],
    ['/devotions/reading-plans/bible-in-a-year', '/'],
    ['/devotions/scripture', '/'],
    ['/worship', '/'],
    ['/worship/morning', '/'],
    ['/worship/morning/complete', '/'],
    ['/programs', '/library'],
    ['/programs/catechizing-shorter-catechism', '/library/westminster-shorter-catechism'],
    ['/programs/catechizing-shorter-catechism/session', '/library/westminster-shorter-catechism'],
    ['/programs/catechizing-larger-catechism', '/library/westminster-larger-catechism'],
    ['/programs/catechizing-heidelberg-catechism/prayer/3', '/library/heidelberg-catechism'],
    ['/programs/catechism-for-young-children', '/library'],
  ];

  test.each(cases)('%s 301s to %s', async (path, destination) => {
    const rule = await resolve(path);
    expect(rule?.destination).toBe(destination);
    expect(rule?.statusCode).toBe(301);
  });

  test('surviving routes are not redirected', async () => {
    for (const path of ['/', '/library', '/reflections', '/search', '/library/westminster-shorter-catechism']) {
      expect(await resolve(path)).toBeNull();
    }
  });
});

describe('sitemap', () => {
  test('lists no cut route', async () => {
    const urls = (await sitemap()).map(({ url }) => new URL(url).pathname);
    expect(urls.filter((u) => /^\/(devotions|worship|programs)(\/|$)/.test(u))).toEqual([]);
    expect(urls).toContain('/library');
  });
});

describe('v1 sitemap routes redirect permanently', () => {
  test.each([
    ['/about', '/'],
    ['/study', '/reflections'],
    ['/westminster-shorter-catechism', '/library/:confession'],
    ['/westminster-shorter-catechism/1', '/library/:confession/:a'],
    ['/westminster-confession-of-faith/1/1', '/library/:confession/:a-:b'],
    ['/canons-of-dort/1/articles/1', '/library/:confession/:a-:b-:c'],
  ])('%s 301s to %s', async (path, destination) => {
    const rule = await resolve(path);
    expect(rule?.destination).toBe(destination);
    expect(rule?.statusCode).toBe(301);
  });
});
