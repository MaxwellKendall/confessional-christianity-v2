// Small zero-dependency fetch client against Cognito's public JSON-RPC API
// (AWSCognitoIdentityProviderService) for passwordless email-code sign-in
// against the shared studio Cognito pool (TKL-1043).
//
// Chosen over aws-amplify/auth because this page only needs 6 public Cognito
// actions (SignUp, ConfirmSignUp, ResendConfirmationCode, InitiateAuth,
// RespondToAuthChallenge, RevokeToken), needs no OAuth callback URLs, and
// avoids adding aws-amplify's large transitive dependency tree and bundle.

import type { PublicCognitoConfig } from './config';
import type { AccountUser, CodePurpose } from './machine';

export interface StoredSession {
  idToken: string;
  accessToken: string;
  refreshToken: string;
  /** Epoch milliseconds when the ID/access tokens expire. */
  expiresAt: number;
}

export interface CognitoStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export class CognitoApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, message: string, status = 400) {
    super(message);
    this.name = 'CognitoApiError';
    this.code = code;
    this.status = status;
  }
}

export interface SendCodeResult {
  purpose: CodePurpose;
  session?: string;
}

export type VerifyCodeResult =
  | { kind: 'signedIn'; tokens: StoredSession; user: AccountUser }
  | { kind: 'awaitingSignInCode'; session: string; notice: string };

interface CognitoAuthResult {
  IdToken?: string;
  AccessToken?: string;
  RefreshToken?: string;
  ExpiresIn?: number;
}

const STORAGE_PREFIX = 'cc.studio.auth.v1';

const storageKey = (config: PublicCognitoConfig) =>
  `${STORAGE_PREFIX}:${config.userPoolId}:${config.clientId}`;

const cognitoEndpoint = (region: string) => `https://cognito-idp.${region}.amazonaws.com/`;

const normalizeErrorCode = (rawType: unknown): string => {
  if (typeof rawType !== 'string' || !rawType) return 'UnknownError';
  const hashIndex = rawType.lastIndexOf('#');
  const trimmed = hashIndex >= 0 ? rawType.slice(hashIndex + 1) : rawType;
  const colonIndex = trimmed.indexOf(':');
  return colonIndex >= 0 ? trimmed.slice(0, colonIndex) : trimmed;
};

async function cognitoCall<T extends Record<string, unknown>>(
  region: string,
  target: string,
  body: Record<string, unknown>,
  fetchImpl: typeof fetch = fetch,
): Promise<T> {
  const response = await fetchImpl(cognitoEndpoint(region), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityProviderService.${target}`,
    },
    body: JSON.stringify(body),
  });

  let data: Record<string, unknown> = {};
  try {
    data = (await response.json()) as Record<string, unknown>;
  } catch {
    // Non-JSON response falls through to generic error below.
  }

  if (!response.ok) {
    const code = normalizeErrorCode(data.__type ?? response.headers.get('x-amzn-errortype'));
    const message =
      (typeof data.message === 'string' && data.message) ||
      (typeof data.Message === 'string' && data.Message) ||
      `Sign-in request failed (${response.status}).`;
    throw new CognitoApiError(code, message, response.status);
  }

  return data as T;
}

/**
 * Decodes the payload of a JWT without verifying its signature (display helper;
 * server-side verification uses @studio/auth).
 */
export const decodeJwtPayload = (token: string): Record<string, unknown> | null => {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), '=');
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    const json = new TextDecoder().decode(bytes);
    const parsed = JSON.parse(json);
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, unknown>) : null;
  } catch {
    return null;
  }
};

export const userFromIdToken = (idToken: string, fallbackEmail?: string | null): AccountUser | null => {
  const payload = decodeJwtPayload(idToken);
  if (!payload || typeof payload.sub !== 'string' || !payload.sub) return null;
  const email = typeof payload.email === 'string' && payload.email ? payload.email : (fallbackEmail ?? null);
  return { sub: payload.sub, email };
};

const toStoredSession = (
  auth: CognitoAuthResult | undefined,
  existingRefreshToken?: string,
): StoredSession => {
  const idToken = auth?.IdToken;
  const accessToken = auth?.AccessToken;
  const refreshToken = auth?.RefreshToken ?? existingRefreshToken ?? '';
  if (!idToken || !accessToken) {
    throw new CognitoApiError('MissingTokens', 'Cognito did not return session tokens.');
  }
  const expiresInSec = typeof auth.ExpiresIn === 'number' && auth.ExpiresIn > 0 ? auth.ExpiresIn : 3600;
  return {
    idToken,
    accessToken,
    refreshToken,
    expiresAt: Date.now() + expiresInSec * 1000,
  };
};

export const friendlyAuthError = (error: unknown): string => {
  const code =
    error && typeof error === 'object' && 'code' in error && typeof error.code === 'string'
      ? error.code
      : '';
  switch (code) {
    case 'CodeMismatchException':
      return "That code isn't right. Check the email and try again.";
    case 'ExpiredCodeException':
      return 'That code has expired. Send a new one.';
    case 'NotAuthorizedException':
      return 'That sign-in code is no longer valid. Send a new one.';
    case 'LimitExceededException':
    case 'TooManyRequestsException':
      return 'Too many attempts. Wait a moment and try again.';
    case 'InvalidParameterException':
      return 'Please check your email address and try again.';
    default:
      if (error instanceof Error && error.message) return error.message;
      return 'Something went wrong. Please try again.';
  }
};

/**
 * Mirrors AuthService.swift: tries passwordless SignUp first (6-digit code)
 * because the pool hides user existence on sign-in, then falls back to
 * USER_AUTH + EMAIL_OTP (8-digit code) when UsernameExistsException is returned.
 */
export async function sendCode(
  config: PublicCognitoConfig,
  email: string,
  fetchImpl: typeof fetch = fetch,
): Promise<SendCodeResult> {
  try {
    const signUp = await cognitoCall<{ Session?: string }>(
      config.region,
      'SignUp',
      {
        ClientId: config.clientId,
        Username: email,
        UserAttributes: [{ Name: 'email', Value: email }],
      },
      fetchImpl,
    );
    return signUp.Session ? { purpose: 'signUp', session: signUp.Session } : { purpose: 'signUp' };
  } catch (error) {
    if (!(error instanceof CognitoApiError) || error.code !== 'UsernameExistsException') {
      throw error;
    }
  }

  try {
    const init = await cognitoCall<{ ChallengeName?: string; Session?: string }>(
      config.region,
      'InitiateAuth',
      {
        ClientId: config.clientId,
        AuthFlow: 'USER_AUTH',
        AuthParameters: {
          USERNAME: email,
          PREFERRED_CHALLENGE: 'EMAIL_OTP',
        },
      },
      fetchImpl,
    );
    if (init.ChallengeName !== 'EMAIL_OTP' || !init.Session) {
      throw new CognitoApiError('UnexpectedChallenge', 'Could not start email code sign-in. Please try again.');
    }
    return { purpose: 'signIn', session: init.Session };
  } catch (error) {
    if (error instanceof CognitoApiError && error.code === 'UserNotConfirmedException') {
      await cognitoCall(
        config.region,
        'ResendConfirmationCode',
        { ClientId: config.clientId, Username: email },
        fetchImpl,
      );
      return { purpose: 'signUp' };
    }
    throw error;
  }
}

export async function verifyCode(
  config: PublicCognitoConfig,
  params: { email: string; code: string; purpose: CodePurpose; session?: string },
  fetchImpl: typeof fetch = fetch,
  onSignUpConfirmed?: () => void,
): Promise<VerifyCodeResult> {
  const { email, code, purpose, session } = params;

  if (purpose === 'signIn') {
    if (!session) {
      throw new CognitoApiError('NotAuthorizedException', 'Your sign-in session expired. Send a new code.');
    }
    const resp = await cognitoCall<{ AuthenticationResult?: CognitoAuthResult }>(
      config.region,
      'RespondToAuthChallenge',
      {
        ClientId: config.clientId,
        ChallengeName: 'EMAIL_OTP',
        Session: session,
        ChallengeResponses: {
          USERNAME: email,
          EMAIL_OTP_CODE: code,
        },
      },
      fetchImpl,
    );
    const tokens = toStoredSession(resp.AuthenticationResult);
    const user = userFromIdToken(tokens.idToken, email);
    if (!user) throw new CognitoApiError('InvalidToken', 'Signed-in token is missing account information.');
    return { kind: 'signedIn', tokens, user };
  }

  // First-time sign-up confirmation (6-digit code)
  const confirmed = await cognitoCall<{ Session?: string }>(
    config.region,
    'ConfirmSignUp',
    {
      ClientId: config.clientId,
      Username: email,
      ConfirmationCode: code,
      ...(session ? { Session: session } : {}),
    },
    fetchImpl,
  );
  onSignUpConfirmed?.();

  // When ConfirmSignUp returns a session, finish auto-sign-in without a second email.
  if (confirmed.Session) {
    const auto = await cognitoCall<{ AuthenticationResult?: CognitoAuthResult }>(
      config.region,
      'InitiateAuth',
      {
        ClientId: config.clientId,
        AuthFlow: 'USER_AUTH',
        Session: confirmed.Session,
        AuthParameters: { USERNAME: email },
      },
      fetchImpl,
    );
    if (auto.AuthenticationResult) {
      const tokens = toStoredSession(auto.AuthenticationResult);
      const user = userFromIdToken(tokens.idToken, email);
      if (!user) throw new CognitoApiError('InvalidToken', 'Signed-in token is missing account information.');
      return { kind: 'signedIn', tokens, user };
    }
  }

  // Fallback when no auto-sign-in session is available (e.g. after ResendConfirmationCode):
  // immediately initiate an 8-digit EMAIL_OTP sign-in code.
  const init = await cognitoCall<{ ChallengeName?: string; Session?: string }>(
    config.region,
    'InitiateAuth',
    {
      ClientId: config.clientId,
      AuthFlow: 'USER_AUTH',
      AuthParameters: {
        USERNAME: email,
        PREFERRED_CHALLENGE: 'EMAIL_OTP',
      },
    },
    fetchImpl,
  );
  if (init.ChallengeName !== 'EMAIL_OTP' || !init.Session) {
    throw new CognitoApiError('UnexpectedChallenge', 'Account confirmed. Send a new code to sign in.');
  }
  return {
    kind: 'awaitingSignInCode',
    session: init.Session,
    notice: 'Email confirmed. Enter the 8-digit sign-in code we just sent.',
  };
}

export const saveSession = (
  config: PublicCognitoConfig,
  session: StoredSession,
  storage: CognitoStorage = window.localStorage,
): void => {
  try {
    storage.setItem(storageKey(config), JSON.stringify(session));
  } catch {
    // Storage may be unavailable in restricted browsing contexts.
  }
};

export const loadSession = (
  config: PublicCognitoConfig,
  storage: CognitoStorage = window.localStorage,
): StoredSession | null => {
  try {
    const raw = storage.getItem(storageKey(config));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredSession>;
    if (
      typeof parsed.idToken !== 'string' ||
      typeof parsed.accessToken !== 'string' ||
      typeof parsed.refreshToken !== 'string' ||
      typeof parsed.expiresAt !== 'number'
    ) {
      return null;
    }
    return {
      idToken: parsed.idToken,
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
      expiresAt: parsed.expiresAt,
    };
  } catch {
    return null;
  }
};

export const clearSession = (
  config: PublicCognitoConfig,
  storage: CognitoStorage = window.localStorage,
): void => {
  try {
    storage.removeItem(storageKey(config));
  } catch {
    // Ignore storage errors.
  }
};

export async function restoreSession(
  config: PublicCognitoConfig,
  storage: CognitoStorage = window.localStorage,
  fetchImpl: typeof fetch = fetch,
): Promise<{ tokens: StoredSession; user: AccountUser } | null> {
  const existing = loadSession(config, storage);
  if (!existing) return null;

  // Still valid for at least 60 s: restore immediately with zero network latency.
  if (existing.expiresAt - 60_000 > Date.now()) {
    const user = userFromIdToken(existing.idToken);
    if (user) return { tokens: existing, user };
  }

  if (!existing.refreshToken) {
    clearSession(config, storage);
    return null;
  }

  try {
    const refreshed = await cognitoCall<{ AuthenticationResult?: CognitoAuthResult }>(
      config.region,
      'InitiateAuth',
      {
        ClientId: config.clientId,
        AuthFlow: 'REFRESH_TOKEN_AUTH',
        AuthParameters: { REFRESH_TOKEN: existing.refreshToken },
      },
      fetchImpl,
    );
    const tokens = toStoredSession(refreshed.AuthenticationResult, existing.refreshToken);
    const user = userFromIdToken(tokens.idToken);
    if (!user) {
      clearSession(config, storage);
      return null;
    }
    saveSession(config, tokens, storage);
    return { tokens, user };
  } catch {
    clearSession(config, storage);
    return null;
  }
}

/**
 * Signs out this browser only: clears localStorage immediately and best-effort
 * revokes this browser's refresh token (leaving the iOS app signed in).
 */
/**
 * Clears this browser's session synchronously, then revokes its refresh token in
 * the background. Callers switch to guest at once; `revoked` never rejects, so a
 * slow or offline network can't hold a signed-out page on the old account.
 */
export function signOutSession(
  config: PublicCognitoConfig,
  storage: CognitoStorage = window.localStorage,
  fetchImpl: typeof fetch = fetch,
): { revoked: Promise<void> } {
  const existing = loadSession(config, storage);
  clearSession(config, storage);
  if (!existing?.refreshToken) return { revoked: Promise.resolve() };
  const revoked = cognitoCall(
    config.region,
    'RevokeToken',
    { ClientId: config.clientId, Token: existing.refreshToken },
    fetchImpl,
  ).then(
    () => undefined,
    () => undefined, // Local session is already cleared; offline sign-out still succeeds.
  );
  return { revoked };
}
