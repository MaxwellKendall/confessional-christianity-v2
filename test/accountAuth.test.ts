// TKL-1043: state machine, config, Cognito fetch client, and localStorage
// persistence for /account email-code sign-in against the studio Cognito pool.
import { describe, expect, test, vi } from 'vitest';

import {
  clearSession,
  decodeJwtPayload,
  friendlyAuthError,
  loadSession,
  restoreSession,
  saveSession,
  sendCode,
  signOutSession,
  verifyCode,
  type CognitoStorage,
  type StoredSession,
} from '@/lib/account/cognitoClient';
import { parseCognitoRegion, publicCognitoConfig } from '@/lib/account/config';
import {
  accountReducer,
  initialAccountState,
  normalizeCode,
  normalizeEmail,
} from '@/lib/account/machine';

const b64url = (obj: Record<string, unknown>) =>
  Buffer.from(JSON.stringify(obj)).toString('base64url');

const makeJwt = (payload: Record<string, unknown>) =>
  `${b64url({ alg: 'RS256', typ: 'JWT' })}.${b64url(payload)}.sig`;

const makeMemoryStorage = (): CognitoStorage & { store: Map<string, string> } => {
  const store = new Map<string, string>();
  return {
    store,
    getItem: (key) => store.get(key) ?? null,
    setItem: (key, value) => {
      store.set(key, value);
    },
    removeItem: (key) => {
      store.delete(key);
    },
  };
};

const TEST_CONFIG = {
  userPoolId: 'us-east-1_80qmmpRpD',
  clientId: '138ua04t4vtitttt5uaq72iji2',
  region: 'us-east-1',
};

describe('publicCognitoConfig & parseCognitoRegion', () => {
  test('extracts region from valid user pool IDs', () => {
    expect(parseCognitoRegion('us-east-1_80qmmpRpD')).toBe('us-east-1');
    expect(parseCognitoRegion('eu-west-2_AbCd1234')).toBe('eu-west-2');
    expect(parseCognitoRegion('not-a-pool')).toBeNull();
    expect(parseCognitoRegion('')).toBeNull();
  });

  test('returns config when both NEXT_PUBLIC_COGNITO_* vars are valid', () => {
    expect(
      publicCognitoConfig({
        NEXT_PUBLIC_COGNITO_USER_POOL_ID: ' us-east-1_80qmmpRpD ',
        NEXT_PUBLIC_COGNITO_CLIENT_ID: ' 138ua04t4vtitttt5uaq72iji2 ',
      }),
    ).toEqual(TEST_CONFIG);
  });

  test('returns null when missing, blank, or malformed (shows coming soon with no error)', () => {
    expect(publicCognitoConfig({})).toBeNull();
    expect(publicCognitoConfig({ NEXT_PUBLIC_COGNITO_USER_POOL_ID: 'us-east-1_80qmmpRpD' })).toBeNull();
    expect(
      publicCognitoConfig({
        NEXT_PUBLIC_COGNITO_USER_POOL_ID: 'bad-pool-id',
        NEXT_PUBLIC_COGNITO_CLIENT_ID: '138ua04t4vtitttt5uaq72iji2',
      }),
    ).toBeNull();
  });
});

describe('input normalization', () => {
  test('normalizeEmail trims, lowercases, and rejects invalid addresses', () => {
    expect(normalizeEmail('  Parent@Example.COM  ')).toBe('parent@example.com');
    expect(normalizeEmail('not-an-email')).toBeNull();
    expect(normalizeEmail('a@b')).toBeNull();
    expect(normalizeEmail('a @b.com')).toBeNull();
    expect(normalizeEmail('@b.com')).toBeNull();
    expect(normalizeEmail('a@b..com')).toBeNull();
  });

  test('normalizeCode strips spaces/dashes and accepts 6 or 8 ASCII digits only', () => {
    expect(normalizeCode('123456')).toBe('123456');
    expect(normalizeCode('123 456')).toBe('123456');
    expect(normalizeCode('1234-5678')).toBe('12345678');
    expect(normalizeCode('12345')).toBeNull();
    expect(normalizeCode('1234567')).toBeNull();
    expect(normalizeCode('123456789')).toBeNull();
    expect(normalizeCode('12345a')).toBeNull();
  });
});

describe('accountReducer state machine', () => {
  test('restores guest or signed-in user from restoring', () => {
    const guest = accountReducer(initialAccountState, { type: 'restored', user: null });
    expect(guest).toEqual({ phase: { kind: 'guest' }, error: null });

    const user = { sub: 'sub-1', email: 'a@b.com' };
    const signedIn = accountReducer(initialAccountState, { type: 'restored', user });
    expect(signedIn).toEqual({ phase: { kind: 'signedIn', user }, error: null });
  });

  test('existing user email -> 8-digit code -> wrong code -> right code -> signed in -> sign out', () => {
    let state = accountReducer(initialAccountState, { type: 'restored', user: null });

    // Invalid email stays guest with error
    state = accountReducer(state, { type: 'requestCode', email: 'bad' });
    expect(state.phase).toEqual({ kind: 'guest' });
    expect(state.error).toEqual({ kind: 'invalidEmail' });

    // Valid email -> sendingCode -> awaitingCode(signIn)
    state = accountReducer(state, { type: 'requestCode', email: '  User@Example.com ' });
    expect(state).toEqual({ phase: { kind: 'sendingCode', email: 'user@example.com' }, error: null });

    state = accountReducer(state, { type: 'codeSent' });
    expect(state).toEqual({
      phase: { kind: 'awaitingCode', email: 'user@example.com', purpose: 'signIn' },
      error: null,
    });

    // Invalid code stays awaitingCode
    state = accountReducer(state, { type: 'submitCode', code: '123' });
    expect(state.phase.kind).toBe('awaitingCode');
    expect(state.error).toEqual({ kind: 'invalidCode' });

    // Wrong code fails back to awaitingCode with error
    state = accountReducer(state, { type: 'submitCode', code: '0000 0000' });
    expect(state.phase).toEqual({
      kind: 'verifying',
      email: 'user@example.com',
      code: '00000000',
      purpose: 'signIn',
    });

    state = accountReducer(state, { type: 'verifyFailed', message: "That code isn't right." });
    expect(state).toEqual({
      phase: { kind: 'awaitingCode', email: 'user@example.com', purpose: 'signIn' },
      error: { kind: 'verifyFailed', message: "That code isn't right." },
    });

    // Right code verifies -> signedIn
    state = accountReducer(state, { type: 'submitCode', code: '87654321' });
    state = accountReducer(state, {
      type: 'verified',
      user: { sub: 'sub-123', email: 'user@example.com' },
    });
    expect(state).toEqual({
      phase: { kind: 'signedIn', user: { sub: 'sub-123', email: 'user@example.com' } },
      error: null,
    });

    // Sign out clears back to guest
    state = accountReducer(state, { type: 'signedOut' });
    expect(state).toEqual({ phase: { kind: 'guest' }, error: null });
  });

  test('new user signUp -> 6-digit code -> signUpConfirmed -> signedIn', () => {
    let state = accountReducer(initialAccountState, { type: 'restored', user: null });
    state = accountReducer(state, { type: 'requestCode', email: 'new@example.com' });
    state = accountReducer(state, { type: 'signUpCodeSent' });
    expect(state.phase).toEqual({ kind: 'awaitingCode', email: 'new@example.com', purpose: 'signUp' });

    state = accountReducer(state, { type: 'submitCode', code: '123456' });
    state = accountReducer(state, { type: 'signUpConfirmed' });
    expect(state.phase).toEqual({ kind: 'signingIn', email: 'new@example.com' });

    state = accountReducer(state, {
      type: 'verified',
      user: { sub: 'sub-new', email: 'new@example.com' },
    });
    expect(state.phase).toEqual({
      kind: 'signedIn',
      user: { sub: 'sub-new', email: 'new@example.com' },
    });
  });

  test('signUp without auto-sign-in session transitions to awaitingCode(signIn) with notice', () => {
    let state = accountReducer(initialAccountState, { type: 'restored', user: null });
    state = accountReducer(state, { type: 'requestCode', email: 'new@example.com' });
    state = accountReducer(state, { type: 'signUpCodeSent' });
    state = accountReducer(state, { type: 'submitCode', code: '123456' });
    state = accountReducer(state, { type: 'signUpConfirmed' });
    state = accountReducer(state, {
      type: 'signUpNeedsSignInCode',
      notice: 'Email confirmed. Enter the 8-digit sign-in code we just sent.',
    });
    expect(state).toEqual({
      phase: {
        kind: 'awaitingCode',
        email: 'new@example.com',
        purpose: 'signIn',
        notice: 'Email confirmed. Enter the 8-digit sign-in code we just sent.',
      },
      error: null,
    });
  });

  // [verify] finding 2: a late /api/account/me result must not bring an ended session back.
  test('a late sessionUpdated after sign-out is ignored', () => {
    const user = { sub: 'sub-1', email: 'a@b.com' };
    let state = accountReducer(initialAccountState, { type: 'restored', user });
    state = accountReducer(state, { type: 'signedOut' });
    expect(state).toEqual({ phase: { kind: 'guest' }, error: null });
    state = accountReducer(state, { type: 'sessionUpdated', user });
    expect(state).toEqual({ phase: { kind: 'guest' }, error: null });
  });

  test('a late sessionUpdated does not overwrite a new sign-in flow', () => {
    const user = { sub: 'sub-1', email: 'a@b.com' };
    let state = accountReducer(initialAccountState, { type: 'restored', user });
    state = accountReducer(state, { type: 'signedOut' });
    state = accountReducer(state, { type: 'requestCode', email: 'c@d.com' });
    state = accountReducer(state, { type: 'codeSent' });
    const awaiting = state;
    state = accountReducer(state, { type: 'sessionUpdated', user });
    expect(state).toBe(awaiting);
    state = accountReducer(state, { type: 'submitCode', code: '12345678' });
    const verifying = state;
    expect(accountReducer(state, { type: 'sessionUpdated', user })).toBe(verifying);
  });

  test('a late sessionUpdated for a different account is ignored once someone else signed in', () => {
    const other = { sub: 'sub-2', email: 'c@d.com' };
    const state = accountReducer(initialAccountState, { type: 'restored', user: other });
    expect(
      accountReducer(state, { type: 'sessionUpdated', user: { sub: 'sub-1', email: 'a@b.com' } }),
    ).toBe(state);
  });

  test('sessionUpdated refreshes the details of the account that is signed in', () => {
    let state = accountReducer(initialAccountState, {
      type: 'restored',
      user: { sub: 'sub-1', email: null },
    });
    state = accountReducer(state, { type: 'sessionUpdated', user: { sub: 'sub-1', email: 'a@b.com' } });
    expect(state).toEqual({
      phase: { kind: 'signedIn', user: { sub: 'sub-1', email: 'a@b.com' } },
      error: null,
    });
  });

  test('cancel from awaitingCode returns to guest and clears errors', () => {
    let state = accountReducer(initialAccountState, { type: 'restored', user: null });
    state = accountReducer(state, { type: 'requestCode', email: 'a@b.com' });
    state = accountReducer(state, { type: 'codeSent' });
    state = accountReducer(state, { type: 'submitCode', code: 'bad' });
    expect(state.error).not.toBeNull();
    state = accountReducer(state, { type: 'cancel' });
    expect(state).toEqual({ phase: { kind: 'guest' }, error: null });
  });
});

describe('cognitoClient flows', () => {
  const cognitoResponse = (status: number, body: Record<string, unknown>) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { 'content-type': 'application/x-amz-json-1.1' },
    });

  test('new user: SignUp -> ConfirmSignUp -> auto sign-in via USER_AUTH with Session', async () => {
    const calls: { target: string; body: Record<string, unknown> }[] = [];
    const idToken = makeJwt({ sub: 'sub-new-1', email: 'new@example.com', exp: 9_999_999_999 });
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      const headers = init?.headers as Record<string, string>;
      const target = headers['X-Amz-Target'].split('.').pop()!;
      const body = JSON.parse(String(init?.body));
      calls.push({ target, body });
      if (target === 'SignUp') return cognitoResponse(200, { UserConfirmed: false, Session: 'su-sess' });
      if (target === 'ConfirmSignUp') return cognitoResponse(200, { Session: 'csu-sess' });
      if (target === 'InitiateAuth') {
        return cognitoResponse(200, {
          AuthenticationResult: {
            IdToken: idToken,
            AccessToken: 'acc-1',
            RefreshToken: 'ref-1',
            ExpiresIn: 3600,
          },
        });
      }
      throw new Error(`Unexpected target ${target}`);
    }) as unknown as typeof fetch;

    const sent = await sendCode(TEST_CONFIG, 'new@example.com', fetchImpl);
    expect(sent).toEqual({ purpose: 'signUp', session: 'su-sess' });

    const verified = await verifyCode(
      TEST_CONFIG,
      { email: 'new@example.com', code: '123456', purpose: 'signUp', session: sent.session },
      fetchImpl,
    );
    expect(verified.kind).toBe('signedIn');
    if (verified.kind === 'signedIn') {
      expect(verified.user).toEqual({ sub: 'sub-new-1', email: 'new@example.com' });
      expect(verified.tokens.refreshToken).toBe('ref-1');
    }
    expect(calls.map((c) => c.target)).toEqual(['SignUp', 'ConfirmSignUp', 'InitiateAuth']);
    expect(calls[1].body).toMatchObject({ ConfirmationCode: '123456', Session: 'su-sess' });
    expect(calls[2].body).toMatchObject({ AuthFlow: 'USER_AUTH', Session: 'csu-sess' });
  });

  test('existing user: SignUp UsernameExistsException -> InitiateAuth EMAIL_OTP -> RespondToAuthChallenge', async () => {
    const idToken = makeJwt({ sub: 'sub-existing', email: 'old@example.com', exp: 9_999_999_999 });
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      const target = (init?.headers as Record<string, string>)['X-Amz-Target'].split('.').pop()!;
      const body = JSON.parse(String(init?.body));
      if (target === 'SignUp') {
        return cognitoResponse(400, { __type: 'UsernameExistsException', message: 'User already exists' });
      }
      if (target === 'InitiateAuth') {
        expect(body.AuthFlow).toBe('USER_AUTH');
        expect(body.AuthParameters).toEqual({ USERNAME: 'old@example.com', PREFERRED_CHALLENGE: 'EMAIL_OTP' });
        return cognitoResponse(200, { ChallengeName: 'EMAIL_OTP', Session: 'otp-sess-1' });
      }
      if (target === 'RespondToAuthChallenge') {
        if (body.ChallengeResponses.EMAIL_OTP_CODE === '00000000') {
          return cognitoResponse(400, { __type: 'CodeMismatchException', message: 'Invalid code' });
        }
        return cognitoResponse(200, {
          AuthenticationResult: {
            IdToken: idToken,
            AccessToken: 'acc-2',
            RefreshToken: 'ref-2',
            ExpiresIn: 3600,
          },
        });
      }
      throw new Error(`Unexpected target ${target}`);
    }) as unknown as typeof fetch;

    const sent = await sendCode(TEST_CONFIG, 'old@example.com', fetchImpl);
    expect(sent).toEqual({ purpose: 'signIn', session: 'otp-sess-1' });

    await expect(
      verifyCode(
        TEST_CONFIG,
        { email: 'old@example.com', code: '00000000', purpose: 'signIn', session: sent.session },
        fetchImpl,
      ),
    ).rejects.toMatchObject({ code: 'CodeMismatchException' });

    const ok = await verifyCode(
      TEST_CONFIG,
      { email: 'old@example.com', code: '12345678', purpose: 'signIn', session: sent.session },
      fetchImpl,
    );
    expect(ok.kind).toBe('signedIn');
    if (ok.kind === 'signedIn') {
      expect(ok.user).toEqual({ sub: 'sub-existing', email: 'old@example.com' });
    }
  });

  test('unconfirmed user: UsernameExistsException -> UserNotConfirmedException -> ResendConfirmationCode', async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      const target = (init?.headers as Record<string, string>)['X-Amz-Target'].split('.').pop()!;
      if (target === 'SignUp') return cognitoResponse(400, { __type: 'UsernameExistsException' });
      if (target === 'InitiateAuth') return cognitoResponse(400, { __type: 'UserNotConfirmedException' });
      if (target === 'ResendConfirmationCode') return cognitoResponse(200, { CodeDeliveryDetails: {} });
      throw new Error(`Unexpected target ${target}`);
    }) as unknown as typeof fetch;

    const sent = await sendCode(TEST_CONFIG, 'pending@example.com', fetchImpl);
    expect(sent).toEqual({ purpose: 'signUp' });
  });

  test('localStorage persistence: survives reload, refreshes expired tokens, signOut revokes only this refresh token', async () => {
    const storage = makeMemoryStorage();
    const freshId = makeJwt({ sub: 'sub-99', email: 'saved@example.com' });
    const session: StoredSession = {
      idToken: freshId,
      accessToken: 'acc-fresh',
      refreshToken: 'ref-99',
      expiresAt: Date.now() + 300_000,
    };

    saveSession(TEST_CONFIG, session, storage);
    expect(loadSession(TEST_CONFIG, storage)).toEqual(session);

    // Reload while valid: no network call needed
    const noFetch = vi.fn() as unknown as typeof fetch;
    const restored = await restoreSession(TEST_CONFIG, storage, noFetch);
    expect(restored?.user).toEqual({ sub: 'sub-99', email: 'saved@example.com' });
    expect(noFetch).not.toHaveBeenCalled();

    // Expired access/id token -> refreshes via REFRESH_TOKEN_AUTH
    saveSession(TEST_CONFIG, { ...session, expiresAt: Date.now() - 10_000 }, storage);
    const renewedId = makeJwt({ sub: 'sub-99', email: 'saved@example.com' });
    const refreshFetch = vi.fn(async (_url: string, init?: RequestInit) => {
      const target = (init?.headers as Record<string, string>)['X-Amz-Target'].split('.').pop()!;
      if (target === 'InitiateAuth') {
        return cognitoResponse(200, {
          AuthenticationResult: { IdToken: renewedId, AccessToken: 'acc-renewed', ExpiresIn: 3600 },
        });
      }
      if (target === 'RevokeToken') return cognitoResponse(200, {});
      throw new Error(`Unexpected target ${target}`);
    }) as unknown as typeof fetch;

    const refreshed = await restoreSession(TEST_CONFIG, storage, refreshFetch);
    expect(refreshed?.tokens.accessToken).toBe('acc-renewed');
    expect(refreshed?.tokens.refreshToken).toBe('ref-99');

    // Sign out clears storage and calls RevokeToken (never GlobalSignOut)
    await signOutSession(TEST_CONFIG, storage, refreshFetch).revoked;
    expect(loadSession(TEST_CONFIG, storage)).toBeNull();
    const targets = (refreshFetch as unknown as ReturnType<typeof vi.fn>).mock.calls.map(
      (call) => (call[1].headers as Record<string, string>)['X-Amz-Target'].split('.').pop(),
    );
    expect(targets).toEqual(['InitiateAuth', 'RevokeToken']);

    // clearSession helper
    saveSession(TEST_CONFIG, session, storage);
    clearSession(TEST_CONFIG, storage);
    expect(loadSession(TEST_CONFIG, storage)).toBeNull();
  });

  // [verify] finding 1: sign-out must not wait on a hanging RevokeToken.
  test('signOutSession clears the session at once, even while revocation hangs', () => {
    const storage = makeMemoryStorage();
    saveSession(
      TEST_CONFIG,
      {
        idToken: makeJwt({ sub: 'sub-1', email: 'a@b.com' }),
        accessToken: 'acc',
        refreshToken: 'ref',
        expiresAt: Date.now() + 3_600_000,
      },
      storage,
    );
    const hanging = vi.fn(() => new Promise<Response>(() => {})) as unknown as typeof fetch;
    const result = signOutSession(TEST_CONFIG, storage, hanging);
    expect(loadSession(TEST_CONFIG, storage)).toBeNull();
    expect(storage.store.size).toBe(0);
    expect(hanging).toHaveBeenCalledTimes(1);
    expect(result.revoked).toBeInstanceOf(Promise);
  });

  test('signOutSession revocation never rejects, even when the network fails', async () => {
    const storage = makeMemoryStorage();
    saveSession(
      TEST_CONFIG,
      { idToken: makeJwt({ sub: 'sub-1' }), accessToken: 'acc', refreshToken: 'ref', expiresAt: 0 },
      storage,
    );
    const failing = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    }) as unknown as typeof fetch;
    await expect(signOutSession(TEST_CONFIG, storage, failing).revoked).resolves.toBeUndefined();
    expect(loadSession(TEST_CONFIG, storage)).toBeNull();
  });

  test('decodeJwtPayload and friendlyAuthError handle edge cases safely', () => {
    expect(decodeJwtPayload('not-a-jwt')).toBeNull();
    expect(decodeJwtPayload(makeJwt({ sub: 's1', email: 'e@x.com' }))).toEqual({ sub: 's1', email: 'e@x.com' });
    expect(friendlyAuthError({ code: 'CodeMismatchException', message: 'bad' })).toMatch(/isn't right/i);
    expect(friendlyAuthError({ code: 'ExpiredCodeException', message: 'exp' })).toMatch(/expired/i);
  });
});
