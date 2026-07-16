import type { Metadata } from 'next';

import { WorshipLandingClient } from './WorshipLandingClient';

export const metadata: Metadata = {
  title: 'Family Worship',
  description:
    'A guided order of family worship — about fifteen minutes, together: '
    + 'scripture, confession, singing, the catechism, and prayer, morning and evening.',
};

export default function WorshipPage() {
  return <WorshipLandingClient />;
}
