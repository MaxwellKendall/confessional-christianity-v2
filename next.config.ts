import type { NextConfig } from 'next';

// The v1 reading routes are the site's organic entry point; these 301s are
// non-negotiable and ship with the library surface (migration plan §3).
// The :confession param is constrained to the eight real document slugs so
// the patterns can never shadow /search, /library, or other v2 routes.
const CONFESSION_SLUGS = [
  'westminster-confession-of-faith',
  'westminster-larger-catechism',
  'westminster-shorter-catechism',
  'heidelberg-catechism',
  'canons-of-dort',
  'the-belgic-confession-of-faith',
  'thirty-nine-articles-of-religion',
  'martin-luthers-95-theses',
].join('|');

// former /programs/<slug> -> its catechism's library slug (the Catechism for
// Young Children has no library page and falls through to /library)
const CUT_PROGRAMS = [
  ['catechizing-shorter-catechism', 'westminster-shorter-catechism'],
  ['catechizing-larger-catechism', 'westminster-larger-catechism'],
  ['catechizing-heidelberg-catechism', 'heidelberg-catechism'],
] as const;

const nextConfig: NextConfig = {
  async redirects() {
    return [
      // v1 document pages -> library TOCs
      {
        source: `/:confession(${CONFESSION_SLUGS})`,
        destination: '/library/:confession',
        statusCode: 301,
      },
      // v1 entry pages: the [...entry] catch-all collapses to one dash-joined
      // segment, so each old path depth maps explicitly (docs/DOMAIN.md ids
      // are at most three segments deep: chapter/articles|rejections/number).
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a`,
        destination: '/library/:confession/:a',
        statusCode: 301,
      },
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a/:b`,
        destination: '/library/:confession/:a-:b',
        statusCode: 301,
      },
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a/:b/:c`,
        destination: '/library/:confession/:a-:b-:c',
        statusCode: 301,
      },
      { source: '/about', destination: '/', statusCode: 301 },
      // the commentary index moved to reflections
      { source: '/study', destination: '/reflections', statusCode: 301 },
      // dashboards fold into the homepage child-switcher (convenience only,
      // never indexed)
      { source: '/dashboard', destination: '/', permanent: false },
      { source: '/dashboard/:path*', destination: '/', permanent: false },
      // TKL-856 cut devotions, reading plans, Family Worship and the web
      // catechism session. All of them were in the sitemap, so each 301s to
      // its nearest surviving page: a catechism program to that catechism in
      // the library, everything else to the library index or the homepage.
      ...CUT_PROGRAMS.map(([program, confession]) => ({
        source: `/programs/${program}/:path*`,
        destination: `/library/${confession}`,
        statusCode: 301,
      })),
      { source: '/programs/:path*', destination: '/library', statusCode: 301 },
      { source: '/devotions/:path*', destination: '/', statusCode: 301 },
      { source: '/worship/:path*', destination: '/', statusCode: 301 },
    ];
  },
};

export default nextConfig;
