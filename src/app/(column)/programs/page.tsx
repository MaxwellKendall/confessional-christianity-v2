import type { Metadata } from 'next';

import { ProgramsIndexClient } from './ProgramsIndexClient';

export const metadata: Metadata = {
  title: 'Catechisms',
  description:
    'Historic catechisms with Scripture, prayer, and saved progress.',
  alternates: { canonical: '/programs' },
};

export default function ProgramsPage() {
  return <ProgramsIndexClient />;
}
