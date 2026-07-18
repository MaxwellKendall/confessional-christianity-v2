import type { Metadata } from 'next';

import { ScriptureBrowseClient } from './ScriptureBrowseClient';

export const metadata: Metadata = {
  title: 'Devotions by Scripture',
  description:
    'Browse family devotions by book, chapter, and verse — all 66 books, '
    + 'Genesis through Revelation.',
};

export default function DevotionsByScripturePage() {
  return <ScriptureBrowseClient />;
}
