import type { Metadata } from 'next';
import { Suspense } from 'react';

import { AddChildClient } from './AddChildClient';

export const metadata: Metadata = {
  title: 'Add a Child',
  robots: { index: false },
};

export default function AddChildPage() {
  return (
    <Suspense>
      <AddChildClient />
    </Suspense>
  );
}
