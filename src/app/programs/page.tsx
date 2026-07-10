import type { Metadata } from 'next';

import { ProgramsIndexClient } from './ProgramsIndexClient';

export const metadata: Metadata = {
  title: 'Programs',
  description:
    'Structured ways to read, memorize, and teach the catechisms — at your own pace, or your child’s.',
  alternates: { canonical: '/programs' },
};

export default function ProgramsPage() {
  return <ProgramsIndexClient />;
}
