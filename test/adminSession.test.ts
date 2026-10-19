import { describe, expect, test } from 'vitest';

import {
  SESSION_TTL_SECONDS, adminAccess, createSessionToken, verifySessionToken,
} from '@/lib/admin/session';

describe('admin access', () => {
  test('a password turns on sign-in anywhere', () => {
    expect(adminAccess({ ADMIN_PASSWORD: 'x', NODE_ENV: 'production' })).toBe('password');
    expect(adminAccess({ ADMIN_PASSWORD: 'x', NODE_ENV: 'development' })).toBe('password');
  });

  test('without one the admin is open locally and absent everywhere else', () => {
    expect(adminAccess({ NODE_ENV: 'development' })).toBe('open');
    expect(adminAccess({ NODE_ENV: 'production' })).toBe('disabled');
    expect(adminAccess({ NODE_ENV: 'test' })).toBe('disabled');
  });
});

describe('session tokens', () => {
  const now = Date.UTC(2026, 9, 16);

  test('round-trip until they expire', async () => {
    const token = await createSessionToken(now, 'secret');
    expect(await verifySessionToken(token, now, 'secret')).toBe(true);
    expect(await verifySessionToken(token, now + (SESSION_TTL_SECONDS - 1) * 1000, 'secret')).toBe(true);
    expect(await verifySessionToken(token, now + SESSION_TTL_SECONDS * 1000, 'secret')).toBe(false);
  });

  test('reject another key, a tampered expiry, and junk', async () => {
    const token = await createSessionToken(now, 'secret');
    expect(await verifySessionToken(token, now, 'other')).toBe(false);
    const [expires, signature] = token.split('.');
    expect(await verifySessionToken(`${Number(expires) + 9999}.${signature}`, now, 'secret')).toBe(false);
    expect(await verifySessionToken('garbage', now, 'secret')).toBe(false);
    expect(await verifySessionToken(undefined, now, 'secret')).toBe(false);
    expect(await verifySessionToken(token, now, '')).toBe(false);
  });
});
