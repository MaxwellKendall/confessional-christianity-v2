// TKL-1043: Next.js verifies Cognito tokens via @studio/auth (packages/studio-auth,
// vendored from studio-platform/packages/auth).
import { afterEach, beforeEach, describe, expect, test } from 'vitest';

import {
  studioAuthConfigFromEnv,
  verifyStudioAccessToken,
  verifyStudioToken,
} from '@/lib/lordsDay/auth';
import { handleAccountMeRequest } from '@/lib/account/meHandler';

import { createTestPool, otherSigningKey, TEST_CLIENT_ID, TEST_POOL_ID, type TestPool } from './support/cognitoJwt';

let pool: TestPool;

beforeEach(() => {
  delete process.env.STUDIO_USER_POOL_ID;
  delete process.env.STUDIO_CLIENT_ID;
  delete process.env.COGNITO_USER_POOL_ID;
  delete process.env.COGNITO_CLIENT_ID;
  pool = createTestPool();
});

afterEach(() => {
  delete process.env.STUDIO_USER_POOL_ID;
  delete process.env.STUDIO_CLIENT_ID;
  delete process.env.COGNITO_USER_POOL_ID;
  delete process.env.COGNITO_CLIENT_ID;
});

describe('studioAuthConfigFromEnv', () => {
  test('prefers STUDIO_USER_POOL_ID / STUDIO_CLIENT_ID over legacy COGNITO_* vars', () => {
    process.env.STUDIO_USER_POOL_ID = 'us-east-1_Studio1';
    process.env.STUDIO_CLIENT_ID = 'studio-client';
    process.env.COGNITO_USER_POOL_ID = 'us-east-1_Legacy1';
    process.env.COGNITO_CLIENT_ID = 'legacy-client';
    expect(studioAuthConfigFromEnv()).toEqual({
      userPoolId: 'us-east-1_Studio1',
      clientId: 'studio-client',
    });
  });

  test('falls back to COGNITO_USER_POOL_ID / COGNITO_CLIENT_ID when STUDIO_* are unset', () => {
    process.env.COGNITO_USER_POOL_ID = 'us-east-1_80qmmpRpD';
    process.env.COGNITO_CLIENT_ID = '138ua04t4vtitttt5uaq72iji2';
    expect(studioAuthConfigFromEnv()).toEqual({
      userPoolId: 'us-east-1_80qmmpRpD',
      clientId: '138ua04t4vtitttt5uaq72iji2',
    });
  });

  test('returns null when either value is missing or blank, and never mixes STUDIO_* with COGNITO_*', () => {
    process.env.STUDIO_USER_POOL_ID = 'us-east-1_Studio1';
    process.env.STUDIO_CLIENT_ID = '   ';
    process.env.COGNITO_CLIENT_ID = 'legacy-client';
    expect(studioAuthConfigFromEnv()).toBeNull();
  });

  test('falls back to COGNITO_* when STUDIO_* are empty strings', () => {
    process.env.STUDIO_USER_POOL_ID = '   ';
    process.env.STUDIO_CLIENT_ID = '';
    process.env.COGNITO_USER_POOL_ID = 'us-east-1_80qmmpRpD';
    process.env.COGNITO_CLIENT_ID = '138ua04t4vtitttt5uaq72iji2';
    expect(studioAuthConfigFromEnv()).toEqual({
      userPoolId: 'us-east-1_80qmmpRpD',
      clientId: '138ua04t4vtitttt5uaq72iji2',
    });
  });
});

describe('@studio/auth token verification', () => {
  const config = { userPoolId: TEST_POOL_ID, clientId: TEST_CLIENT_ID };

  test('verifyStudioToken accepts both ID and access tokens for the configured client', async () => {
    const idToken = pool.sign({
      token_use: 'id',
      aud: TEST_CLIENT_ID,
      client_id: undefined,
      email: 'parent@example.com',
      products: { confessional: 'plus' },
    });
    const idClaims = await verifyStudioToken(idToken, config, { jwks: pool.jwks as never });
    expect(idClaims.sub).toBe('user-sub-1');
    expect(idClaims.email).toBe('parent@example.com');
    expect(idClaims.products).toEqual({ confessional: 'plus' });

    const accessClaims = await verifyStudioToken(pool.sign(), config, { jwks: pool.jwks as never });
    expect(accessClaims.sub).toBe('user-sub-1');
    expect(accessClaims.token_use).toBe('access');
  });

  test('verifyStudioToken rejects tokens from another product client (isolation)', async () => {
    const otherClientIdToken = pool.sign({ token_use: 'id', aud: 'remix-client', client_id: undefined });
    await expect(verifyStudioToken(otherClientIdToken, config, { jwks: pool.jwks as never })).rejects.toThrow();

    const otherClientAccessToken = pool.sign({ client_id: 'remix-client' });
    await expect(verifyStudioToken(otherClientAccessToken, config, { jwks: pool.jwks as never })).rejects.toThrow();
  });

  test('verifyStudioAccessToken accepts access tokens and rejects ID tokens', async () => {
    const ok = await verifyStudioAccessToken(pool.sign({ sub: 'sub-abc' }), config, { jwks: pool.jwks as never });
    expect(ok.sub).toBe('sub-abc');

    const idToken = pool.sign({ token_use: 'id', aud: TEST_CLIENT_ID, client_id: undefined });
    await expect(verifyStudioAccessToken(idToken, config, { jwks: pool.jwks as never })).rejects.toThrow();
  });
});

describe('GET /api/account/me', () => {
  const config = { userPoolId: TEST_POOL_ID, clientId: TEST_CLIENT_ID };
  const req = (token?: string) =>
    new Request('http://localhost/api/account/me', {
      method: 'GET',
      headers: token ? { authorization: `Bearer ${token}` } : {},
    });

  test('returns 503 when auth is not configured', async () => {
    const res = await handleAccountMeRequest(req(), null);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: 'auth_not_configured' });
  });

  test('returns 401 for missing, invalid, wrong-client, or foreign-key tokens', async () => {
    for (const token of [
      undefined,
      'not.a.jwt',
      pool.sign({ client_id: 'other-client' }),
      pool.sign({}, otherSigningKey()),
    ]) {
      const res = await handleAccountMeRequest(req(token), config, { jwks: pool.jwks as never });
      expect(res.status).toBe(401);
      expect(await res.json()).toEqual({ error: 'unauthorized' });
    }
  });

  test('returns 200 with verified sub, email and products for a valid ID token', async () => {
    const idToken = pool.sign({
      sub: 'studio-sub-42',
      token_use: 'id',
      aud: TEST_CLIENT_ID,
      client_id: undefined,
      email: 'member@example.com',
      products: { confessional: 'plus' },
    });
    const res = await handleAccountMeRequest(req(idToken), config, { jwks: pool.jwks as never });
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(await res.json()).toEqual({
      sub: 'studio-sub-42',
      email: 'member@example.com',
      tokenUse: 'id',
      products: { confessional: 'plus' },
    });
  });
});
