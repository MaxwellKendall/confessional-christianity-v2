import type { Metadata } from 'next';

import { AuthForm } from '@/components/AuthForm';

export const metadata: Metadata = {
  title: 'Create an Account',
  robots: { index: false },
};

export default function SignUpPage() {
  return <AuthForm mode="signup" />;
}
