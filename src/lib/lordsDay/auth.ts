import { CognitoJwtVerifier } from 'aws-jwt-verify';

// The app signs in against the stage's Cognito pool (infra/, TKL-850). The
// generator accepts only that pool's *access* tokens for the iOS app client;
// the subject it verifies is what the rate limit keys on.

export interface CognitoConfig {
  userPoolId: string;
  clientId: string;
}

export const cognitoConfigFromEnv = (): CognitoConfig | null => {
  const userPoolId = process.env.COGNITO_USER_POOL_ID?.trim();
  const clientId = process.env.COGNITO_CLIENT_ID?.trim();
  return userPoolId && clientId ? { userPoolId, clientId } : null;
};

export const createCognitoVerifier = ({ userPoolId, clientId }: CognitoConfig) =>
  CognitoJwtVerifier.create({ userPoolId, clientId, tokenUse: 'access' });

let cached: { key: string; verifier: ReturnType<typeof createCognitoVerifier> } | null = null;

/** One verifier per warm instance, so the pool's JWKS is fetched once and cached. */
export const verifierFor = (config: CognitoConfig) => {
  const key = `${config.userPoolId}:${config.clientId}`;
  if (cached?.key !== key) cached = { key, verifier: createCognitoVerifier(config) };
  return cached.verifier;
};

export const bearerToken = (request: Request): string | null =>
  /^Bearer\s+(\S+)$/i.exec(request.headers.get('authorization') ?? '')?.[1] ?? null;
