import type { Metadata } from 'next';
import { Suspense } from 'react';

import { SearchClient } from '@/components/SearchClient';

export const metadata: Metadata = {
  title: 'Search',
  description:
    'Search the confessions of historic Protestantism by keyword, scripture text, or citation.',
  alternates: { canonical: '/search' },
};

export default function SearchPage() {
  return (
    <Suspense>
      <SearchClient />
    </Suspense>
  );
}
