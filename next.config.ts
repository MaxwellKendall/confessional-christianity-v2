import type { NextConfig } from 'next';

// The v1 reading routes are the site's organic entry point; these 301s are
// non-negotiable and ship with the library surface (migration plan §3).
// The :confession param is constrained to the eight real document slugs so
// the patterns can never shadow /search, /programs, or other v2 routes.
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

const nextConfig: NextConfig = {
  async redirects() {
    return [
      // v1 document pages -> library TOCs
      {
        source: `/:confession(${CONFESSION_SLUGS})`,
        destination: '/library/:confession',
        permanent: true,
      },
      // v1 entry pages: the [...entry] catch-all collapses to one dash-joined
      // segment, so each old path depth maps explicitly (docs/DOMAIN.md ids
      // are at most three segments deep: chapter/articles|rejections/number).
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a`,
        destination: '/library/:confession/:a',
        permanent: true,
      },
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a/:b`,
        destination: '/library/:confession/:a-:b',
        permanent: true,
      },
      {
        source: `/:confession(${CONFESSION_SLUGS})/:a/:b/:c`,
        destination: '/library/:confession/:a-:b-:c',
        permanent: true,
      },
      // the commentary index moved to reflections
      { source: '/study', destination: '/reflections', permanent: true },
      // dashboards fold into the homepage child-switcher (convenience only,
      // never indexed)
      { source: '/dashboard', destination: '/', permanent: false },
      { source: '/dashboard/:path*', destination: '/', permanent: false },
    ];
  },
};

export default nextConfig;
