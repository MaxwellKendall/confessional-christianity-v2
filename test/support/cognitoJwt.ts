import { createPrivateKey, createPublicKey, createSign, type KeyObject } from 'crypto';
import { readFileSync } from 'fs';
import path from 'path';

// A local stand-in for a Cognito user pool: an RSA key whose public half is
// handed to the verifier as its cached JWKS, so tokens verify fully offline.
export const TEST_POOL_ID = 'us-east-1_TestPool1';
export const TEST_CLIENT_ID = 'testclient1234567890';
export const TEST_ISSUER = `https://cognito-idp.us-east-1.amazonaws.com/${TEST_POOL_ID}`;

const KID = 'test-key-1';

const b64url = (input: Buffer | string) =>
  Buffer.from(input).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

export interface TestPool {
  jwks: { keys: Record<string, unknown>[] };
  sign: (claims?: Record<string, unknown>, privateKey?: KeyObject) => string;
}

// Fixed test-only keys (test/support/keys/README.md): generating RSA keys per
// test took over 10 s under load and broke vitest's timeouts (TKL-981).
const loadKey = (name: string) =>
  createPrivateKey(readFileSync(path.join(__dirname, 'keys', `${name}.test-only.pem`)));
const poolPrivateKey = loadKey('pool');
const poolPublicKey = createPublicKey(poolPrivateKey);
const foreignPrivateKey = loadKey('other');

/** A private key the pool's JWKS does not contain, for "signed by a different key" cases. */
export const otherSigningKey = (): KeyObject => foreignPrivateKey;

export const createTestPool = (): TestPool => {
  const jwk = { ...poolPublicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };
  const sign = (claims: Record<string, unknown> = {}, key: KeyObject = poolPrivateKey) => {
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      sub: 'user-sub-1',
      iss: TEST_ISSUER,
      client_id: TEST_CLIENT_ID,
      token_use: 'access',
      scope: 'aws.cognito.signin.user.admin',
      iat: now,
      exp: now + 3600,
      ...claims,
    };
    const head = b64url(JSON.stringify({ alg: 'RS256', kid: KID, typ: 'JWT' }));
    const body = b64url(JSON.stringify(payload));
    const signer = createSign('RSA-SHA256');
    signer.update(`${head}.${body}`);
    return `${head}.${body}.${b64url(signer.sign(key))}`;
  };
  return { jwks: { keys: [jwk] }, sign };
};
