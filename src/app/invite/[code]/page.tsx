import type { Metadata } from 'next';

import { InviteClient } from './InviteClient';

export const metadata: Metadata = {
  title: 'Invite',
  robots: { index: false },
};

export default async function InvitePage(
  { params }: { params: Promise<{ code: string }> },
) {
  const { code } = await params;
  return <InviteClient code={code} />;
}
