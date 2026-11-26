import type { Metadata } from 'next';

import { AccountClient } from '@/components/AccountClient';
import { publicCognitoConfig } from '@/lib/account/config';

// Read public Cognito env vars per request so deployments pick up config
// changes without requiring a rebuild, while missing config cleanly shows
// "Accounts are coming soon."
export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Account',
  description: 'Sign in to your Confessional Christianity account.',
  robots: { index: false, follow: false },
};

export default function AccountPage() {
  const config = publicCognitoConfig();
  return <AccountClient config={config} />;
}
