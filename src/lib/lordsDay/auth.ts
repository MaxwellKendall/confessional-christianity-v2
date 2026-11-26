import { verify, type StudioClaims, type VerifyOptions } from '@studio/auth';

// Server-side Cognito token verification backed by @studio/auth (TKL-1043;
// vendored from studio-platform/packages/auth). Accepts STUDIO_USER_POOL_ID /
// STUDIO_CLIENT_ID first and falls back to the legacy COGNITO_* names so
// existing production deployments stay configured without interruption.

export interface CognitoConfig {
  userPoolId: string;
  clientId: string;
}

export const studioAuthConfigFromEnv = (env: NodeJS.ProcessEnv = process.env): CognitoConfig | null => {
  const studioPool = env.STUDIO_USER_POOL_ID?.trim();
  const studioClient = env.STUDIO_CLIENT_ID?.trim();
  if (studioPool || studioClient) {
    return studioPool && studioClient ? { userPoolId: studioPool, clientId: studioClient } : null;
  }
  const legacyPool = env.COGNITO_USER_POOL_ID?.trim();
  const legacyClient = env.COGNITO_CLIENT_ID?.trim();
  return legacyPool && legacyClient ? { userPoolId: legacyPool, clientId: legacyClient } : null;
};

/** Backwards-compatible alias for studioAuthConfigFromEnv. */
export const cognitoConfigFromEnv = studioAuthConfigFromEnv;

export const verifyStudioToken = (
  token: string,
  config: CognitoConfig,
  opts: Pick<VerifyOptions, 'jwks'> = {},
): Promise<StudioClaims> =>
  verify(token, config.clientId, {
    userPoolId: config.userPoolId,
    jwks: opts.jwks,
  });

/**
 * Verifies an access token issued to this product's studio client.
 * Rejects ID tokens so API endpoints that expect access tokens stay strict.
 */
export const verifyStudioAccessToken = async (
  token: string,
  config: CognitoConfig,
  opts: Pick<VerifyOptions, 'jwks'> = {},
): Promise<{ sub: string; claims: StudioClaims }> => {
  const claims = await verifyStudioToken(token, config, opts);
  if (claims.token_use !== 'access') {
    throw new Error('Expected an access token');
  }
  return { sub: String(claims.sub), claims };
};

export const bearerToken = (request: Request): string | null =>
  /^Bearer\s+(\S+)$/i.exec(request.headers.get('authorization') ?? '')?.[1] ?? null;
