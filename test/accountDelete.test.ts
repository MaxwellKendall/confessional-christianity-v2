import { generateKeyPairSync, verify } from 'crypto';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

const getUser = vi.fn();
const deleteUser = vi.fn();

vi.mock('@/lib/supabaseServiceRole', () => ({
  getSupabaseServiceRole: () => ({ auth: { getUser, admin: { deleteUser } } }),
}));

const { POST } = await import('@/app/api/account/delete/route');
const { makeAppleClientSecret } = await import('@/lib/appleRevoke');

const USER_ID = '11111111-1111-1111-1111-111111111111';
const APPLE_ENV = ['APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_CLIENT_ID', 'APPLE_PRIVATE_KEY'] as const;

const request = (headers: Record<string, string> = {}, body?: unknown) =>
  new Request('http://localhost/api/account/delete', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

const userWith = (providers: string[]) => ({
  data: { user: { id: USER_ID, identities: providers.map((provider) => ({ provider })) } },
  error: null,
});

const setAppleEnv = () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  process.env.APPLE_TEAM_ID = 'TEAM123456';
  process.env.APPLE_KEY_ID = 'KEY1234567';
  process.env.APPLE_CLIENT_ID = 'com.confessionalchristianity.app';
  process.env.APPLE_PRIVATE_KEY = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
};

beforeEach(() => {
  getUser.mockReset();
  deleteUser.mockReset().mockResolvedValue({ data: {}, error: null });
  APPLE_ENV.forEach((name) => delete process.env[name]);
  vi.spyOn(console, 'info').mockImplementation(() => {});
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('POST /api/account/delete', () => {
  test('no Authorization header → 401, nothing deleted', async () => {
    const res = await POST(request());
    expect(res.status).toBe(401);
    expect(getUser).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('non-Bearer Authorization header → 401', async () => {
    const res = await POST(request({ authorization: 'Basic abc' }));
    expect(res.status).toBe(401);
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('invalid JWT → 401, nothing deleted', async () => {
    getUser.mockResolvedValue({ data: { user: null }, error: { message: 'invalid JWT' } });
    const res = await POST(request({ authorization: 'Bearer bad-token' }));
    expect(res.status).toBe(401);
    expect(getUser).toHaveBeenCalledWith('bad-token');
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('valid JWT → 200 {deleted: true}, deletes the JWT subject only', async () => {
    getUser.mockResolvedValue(userWith(['email']));
    const res = await POST(
      request({ authorization: 'Bearer good-token' }, { userId: '99999999-9999-9999-9999-999999999999' }),
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });
    expect(getUser).toHaveBeenCalledWith('good-token');
    expect(deleteUser).toHaveBeenCalledTimes(1);
    expect(deleteUser).toHaveBeenCalledWith(USER_ID);
  });

  test('deleteUser error → 500, not reported as deleted', async () => {
    getUser.mockResolvedValue(userWith(['email']));
    deleteUser.mockResolvedValue({ data: null, error: { message: 'boom' } });
    const res = await POST(request({ authorization: 'Bearer good-token' }));
    expect(res.status).toBe(500);
    expect(await res.json()).not.toHaveProperty('deleted', true);
  });

  test('Apple user without Apple env vars → logs a skip, still deletes', async () => {
    getUser.mockResolvedValue(userWith(['apple']));
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleRefreshToken: 'rt' }));
    expect(res.status).toBe(200);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(console.info).toHaveBeenCalledWith(expect.stringContaining('Apple token revoke skipped'));
    expect(deleteUser).toHaveBeenCalledWith(USER_ID);
  });

  test('Apple user with env vars and refresh token → revokes it before deleting', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    const calls: string[] = [];
    const fetchMock = vi.fn(async (url: string) => {
      calls.push(url);
      return new Response('', { status: 200 });
    });
    deleteUser.mockImplementation(async () => {
      calls.push('deleteUser');
      return { data: {}, error: null };
    });
    vi.stubGlobal('fetch', fetchMock);

    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleRefreshToken: 'apple-rt' }));
    expect(res.status).toBe(200);
    expect(calls).toEqual(['https://appleid.apple.com/auth/revoke', 'deleteUser']);
    const body = new URLSearchParams(String(fetchMock.mock.calls[0][1].body));
    expect(body.get('token')).toBe('apple-rt');
    expect(body.get('token_type_hint')).toBe('refresh_token');
    expect(body.get('client_id')).toBe('com.confessionalchristianity.app');
    expect(body.get('client_secret')?.split('.')).toHaveLength(3);
  });

  test('Apple user with authorization code → exchanges it, then revokes the refresh token', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    const fetchMock = vi.fn(async (url: string) =>
      url.endsWith('/auth/token')
        ? Response.json({ refresh_token: 'exchanged-rt' })
        : new Response('', { status: 200 }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleAuthorizationCode: 'code-1' }));
    expect(res.status).toBe(200);
    expect(fetchMock.mock.calls.map((c) => c[0])).toEqual([
      'https://appleid.apple.com/auth/token',
      'https://appleid.apple.com/auth/revoke',
    ]);
    const tokenBody = new URLSearchParams(String(fetchMock.mock.calls[0][1].body));
    expect(tokenBody.get('code')).toBe('code-1');
    expect(tokenBody.get('grant_type')).toBe('authorization_code');
    const revokeBody = new URLSearchParams(String(fetchMock.mock.calls[1][1].body));
    expect(revokeBody.get('token')).toBe('exchanged-rt');
    expect(deleteUser).toHaveBeenCalledWith(USER_ID);
  });

  test('Apple user with env vars but no credential → 400, nothing deleted', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const res = await POST(request({ authorization: 'Bearer good-token' }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'apple_credential_required' });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('Apple user with env vars and empty-string credentials → 400, nothing deleted', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    vi.stubGlobal('fetch', vi.fn());
    const res = await POST(
      request({ authorization: 'Bearer good-token' }, { appleRefreshToken: '', appleAuthorizationCode: '' }),
    );
    expect(res.status).toBe(400);
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('Apple revoke failure → 502, nothing deleted, so the app can retry', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    vi.stubGlobal('fetch', vi.fn(async () => new Response('bad', { status: 400 })));
    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleRefreshToken: 'rt' }));
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: 'apple_revoke_failed' });
    expect(console.warn).toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('Apple code exchange failure → 502, nothing deleted', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['apple']));
    const fetchMock = vi.fn(async () => Response.json({ error: 'invalid_grant' }, { status: 400 }));
    vi.stubGlobal('fetch', fetchMock);
    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleAuthorizationCode: 'stale' }));
    expect(res.status).toBe(502);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test('non-Apple user never calls Apple, even with env vars set', async () => {
    setAppleEnv();
    getUser.mockResolvedValue(userWith(['email']));
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const res = await POST(request({ authorization: 'Bearer good-token' }, { appleRefreshToken: 'rt' }));
    expect(res.status).toBe(200);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('makeAppleClientSecret', () => {
  test('is an ES256 JWT Apple accepts: header kid, iss/sub/aud claims, verifiable signature', () => {
    const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const jwt = makeAppleClientSecret(
      {
        teamId: 'TEAM123456',
        keyId: 'KEY1234567',
        clientId: 'com.confessionalchristianity.app',
        privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
      },
      1_700_000_000,
    );
    const [h, p, s] = jwt.split('.');
    const decode = (part: string) => JSON.parse(Buffer.from(part, 'base64url').toString());
    expect(decode(h)).toEqual({ alg: 'ES256', kid: 'KEY1234567' });
    expect(decode(p)).toMatchObject({
      iss: 'TEAM123456',
      sub: 'com.confessionalchristianity.app',
      aud: 'https://appleid.apple.com',
      iat: 1_700_000_000,
    });
    expect(decode(p).exp).toBeGreaterThan(1_700_000_000);
    const ok = verify(
      'sha256',
      Buffer.from(`${h}.${p}`),
      { key: publicKey, dsaEncoding: 'ieee-p1363' },
      Buffer.from(s, 'base64url'),
    );
    expect(ok).toBe(true);
  });

  test('accepts a private key whose newlines are escaped (as env vars often store them)', () => {
    const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString().replace(/\n/g, '\\n');
    expect(() =>
      makeAppleClientSecret({ teamId: 't', keyId: 'k', clientId: 'c', privateKey: pem }, 1),
    ).not.toThrow();
  });
});
