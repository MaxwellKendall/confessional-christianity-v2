// /admin access: one shared password (ADMIN_PASSWORD) exchanged for a signed,
// expiring cookie. Deliberately not Supabase accounts — the people who author
// devotions are a handful of editors, and every save still lands as a git
// commit someone reviews, so the password only has to keep the editor itself
// private. Web Crypto only, so the same code runs in proxy.ts and in server
// actions.
//
// Locally (`next dev`) with no ADMIN_PASSWORD set the admin is open; in any
// other environment without one it doesn't exist (proxy.ts 404s it).

export const ADMIN_COOKIE = 'cc_admin';
export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 14;

export type AdminAccess = 'open' | 'password' | 'disabled';

export const adminAccess = (
  env: { ADMIN_PASSWORD?: string; NODE_ENV?: string } = process.env,
): AdminAccess => {
  if (env.ADMIN_PASSWORD) return 'password';
  return env.NODE_ENV === 'development' ? 'open' : 'disabled';
};

const encoder = new TextEncoder();

const secret = (): string => process.env.ADMIN_SESSION_SECRET || process.env.ADMIN_PASSWORD || '';

const hmacHex = async (key: string, message: string): Promise<string> => {
  const cryptoKey = await crypto.subtle.importKey(
    'raw', encoder.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, encoder.encode(message));
  return Array.from(new Uint8Array(signature), (b) => b.toString(16).padStart(2, '0')).join('');
};

/** Compares two strings without short-circuiting on the first mismatch. */
const sameString = (a: string, b: string): boolean => {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
};

/** `<expiry-epoch-seconds>.<hmac>` — the cookie value for a fresh session. */
export const createSessionToken = async (
  now = Date.now(),
  key = secret(),
): Promise<string> => {
  const expires = Math.floor(now / 1000) + SESSION_TTL_SECONDS;
  return `${expires}.${await hmacHex(key, `admin:${expires}`)}`;
};

export const verifySessionToken = async (
  token: string | undefined,
  now = Date.now(),
  key = secret(),
): Promise<boolean> => {
  if (!token || !key) return false;
  const [expiresRaw, signature] = token.split('.');
  const expires = Number(expiresRaw);
  if (!Number.isInteger(expires) || !signature || expires * 1000 <= now) return false;
  return sameString(signature, await hmacHex(key, `admin:${expires}`));
};

/** Hashes both sides first so the comparison leaks nothing about length. */
export const passwordMatches = async (attempt: string): Promise<boolean> => {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) return false;
  const pepper = 'cc-admin-password';
  return sameString(await hmacHex(pepper, attempt), await hmacHex(pepper, expected));
};

/** Whether a request carrying `token` may use the admin right now. */
export const isAdminToken = async (token: string | undefined): Promise<boolean> => {
  const access = adminAccess();
  if (access === 'open') return true;
  if (access === 'disabled') return false;
  return verifySessionToken(token);
};
