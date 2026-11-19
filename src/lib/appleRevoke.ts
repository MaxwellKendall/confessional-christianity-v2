import { createPrivateKey, sign } from 'crypto';

// Sign in with Apple token revocation, required alongside account deletion
// (App Store guideline 5.1.1(v)). Server-only: the .p8 key never leaves it.
// https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

const APPLE = 'https://appleid.apple.com';

export type AppleRevokeConfig = {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKey: string;
};

export function appleRevokeConfigFromEnv(env: NodeJS.ProcessEnv = process.env): AppleRevokeConfig | null {
  const { APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_CLIENT_ID, APPLE_PRIVATE_KEY } = env;
  if (!APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_CLIENT_ID || !APPLE_PRIVATE_KEY) return null;
  return { teamId: APPLE_TEAM_ID, keyId: APPLE_KEY_ID, clientId: APPLE_CLIENT_ID, privateKey: APPLE_PRIVATE_KEY };
}

const b64url = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');

// The client_secret Apple expects: an ES256 JWT signed with the team's key.
export function makeAppleClientSecret(config: AppleRevokeConfig, nowSeconds = Math.floor(Date.now() / 1000)): string {
  const header = b64url({ alg: 'ES256', kid: config.keyId });
  const payload = b64url({
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + 300,
    aud: APPLE,
    sub: config.clientId,
  });
  const key = createPrivateKey(config.privateKey.replace(/\\n/g, '\n'));
  const signature = sign('sha256', Buffer.from(`${header}.${payload}`), { key, dsaEncoding: 'ieee-p1363' });
  return `${header}.${payload}.${signature.toString('base64url')}`;
}

const post = (path: string, params: Record<string, string>) =>
  fetch(`${APPLE}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params).toString(),
  });

export type AppleTokens = { refreshToken?: string; authorizationCode?: string };

export type AppleRevokeResult =
  | { status: 'revoked' }
  | { status: 'skipped'; reason: string }
  | { status: 'failed'; reason: string };

// Revokes the user's Apple refresh token. Supabase does not keep Apple's
// refresh token, so the app sends either the refresh token or a fresh
// authorization code (exchanged here for one). Never throws.
export async function revokeAppleTokens(
  config: AppleRevokeConfig | null,
  tokens: AppleTokens,
): Promise<AppleRevokeResult> {
  if (!config) return { status: 'skipped', reason: 'Apple key env vars not set' };
  if (!tokens.refreshToken && !tokens.authorizationCode) {
    return { status: 'skipped', reason: 'no Apple refresh token or authorization code in the request' };
  }
  try {
    const clientSecret = makeAppleClientSecret(config);
    const base = { client_id: config.clientId, client_secret: clientSecret };
    let refreshToken = tokens.refreshToken;
    if (!refreshToken) {
      const res = await post('/auth/token', {
        ...base,
        code: tokens.authorizationCode!,
        grant_type: 'authorization_code',
      });
      if (!res.ok) return { status: 'failed', reason: `token exchange HTTP ${res.status}` };
      refreshToken = ((await res.json()) as { refresh_token?: string }).refresh_token;
      if (!refreshToken) return { status: 'failed', reason: 'token exchange returned no refresh_token' };
    }
    const res = await post('/auth/revoke', { ...base, token: refreshToken, token_type_hint: 'refresh_token' });
    if (!res.ok) return { status: 'failed', reason: `revoke HTTP ${res.status}` };
    return { status: 'revoked' };
  } catch (error) {
    return { status: 'failed', reason: error instanceof Error ? error.message : String(error) };
  }
}
