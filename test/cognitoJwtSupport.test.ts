// TKL-981: generating a 2048-bit RSA key is a random prime search that took
// 0.3-2 s per key on an idle Mac and over 10 s under load, which blew vitest's
// 5 s / 10 s limits. The test pool signs with fixed, committed test-only keys.
import { readFileSync } from 'fs';
import path from 'path';
import { describe, expect, test } from 'vitest';

import { createTestPool, otherSigningKey } from './support/cognitoJwt';

describe('test Cognito pool', () => {
  test('reuses one key pair across calls', () => {
    expect(createTestPool().jwks).toEqual(createTestPool().jwks);
  });

  test('the foreign signing key is not the pool key', () => {
    const pool = createTestPool();
    const [, , ownSig] = pool.sign().split('.');
    const [, , otherSig] = pool.sign({}, otherSigningKey()).split('.');
    expect(otherSig).not.toBe(ownSig);
  });

  test.each(['support/cognitoJwt.ts', 'lordsDayCardsRoute.test.ts'])('%s generates no RSA keys', (file) => {
    const source = readFileSync(path.join(__dirname, file), 'utf8');
    expect(source).not.toMatch(/generateKeyPair(Sync)?\(\s*'rsa'/);
  });
});
