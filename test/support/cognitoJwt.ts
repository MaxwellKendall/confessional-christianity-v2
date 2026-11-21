import { createSign, generateKeyPairSync, type KeyObject } from 'crypto';

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

export const createTestPool = (): TestPool => {
  const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };
  const sign = (claims: Record<string, unknown> = {}, key: KeyObject = privateKey) => {
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
