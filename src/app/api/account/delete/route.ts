import { NextResponse } from 'next/server';

import { appleRevokeConfigFromEnv, revokeAppleTokens } from '@/lib/appleRevoke';
import { getSupabaseServiceRole } from '@/lib/supabaseServiceRole';

// In-app account deletion (App Store guideline 5.1.1(v)). The caller proves
// who they are with their Supabase access token; the id deleted is always
// that token's subject, never anything from the body. Rows the user owns go
// with the auth user through ON DELETE CASCADE foreign keys on auth.users.
//
// Optional JSON body for Sign in with Apple users:
//   { appleRefreshToken?: string, appleAuthorizationCode?: string }
// Revocation is best effort: a failure is logged and deletion still happens.
export const dynamic = 'force-dynamic';

const unauthorized = () => NextResponse.json({ error: 'unauthorized' }, { status: 401 });

const readBody = async (request: Request): Promise<Record<string, unknown>> => {
  try {
    const body = await request.json();
    return body && typeof body === 'object' ? body : {};
  } catch {
    return {};
  }
};

const optionalString = (value: unknown) => (typeof value === 'string' && value ? value : undefined);

export async function POST(request: Request) {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get('authorization') ?? '');
  if (!match) return unauthorized();
  const jwt = match[1];

  const supabase = getSupabaseServiceRole();
  const { data, error } = await supabase.auth.getUser(jwt);
  const user = data?.user;
  if (error || !user) return unauthorized();

  if (user.identities?.some((identity) => identity.provider === 'apple')) {
    const body = await readBody(request);
    const result = await revokeAppleTokens(appleRevokeConfigFromEnv(), {
      refreshToken: optionalString(body.appleRefreshToken),
      authorizationCode: optionalString(body.appleAuthorizationCode),
    });
    if (result.status === 'skipped') {
      console.info(`[account/delete] Apple token revoke skipped for ${user.id}: ${result.reason}`);
    } else if (result.status === 'failed') {
      console.warn(`[account/delete] Apple token revoke failed for ${user.id}: ${result.reason}`);
    }
  }

  const { error: deleteError } = await supabase.auth.admin.deleteUser(user.id);
  if (deleteError) {
    console.error(`[account/delete] deleteUser failed for ${user.id}: ${deleteError.message}`);
    return NextResponse.json({ error: 'delete failed' }, { status: 500 });
  }
  return NextResponse.json({ deleted: true });
}
