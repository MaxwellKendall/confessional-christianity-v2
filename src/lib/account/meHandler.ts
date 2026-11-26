import type { VerifyOptions } from '@studio/auth';

import { bearerToken, verifyStudioToken, type CognitoConfig } from '@/lib/lordsDay/auth';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  });

/**
 * Stateless Bearer-token verification for /account (TKL-1043).
 * Uses @studio/auth to prove the token belongs to the studio pool's confessional
 * client and returns its verified subject, email (on ID tokens), and product plans.
 */
export const handleAccountMeRequest = async (
  request: Request,
  config: CognitoConfig | null,
  opts: Pick<VerifyOptions, 'jwks'> = {},
): Promise<Response> => {
  if (!config) return json(503, { error: 'auth_not_configured' });

  const token = bearerToken(request);
  if (!token) return json(401, { error: 'unauthorized' });

  try {
    const claims = await verifyStudioToken(token, config, opts);
    return json(200, {
      sub: String(claims.sub),
      email: typeof claims.email === 'string' ? claims.email : null,
      tokenUse: claims.token_use,
      products: claims.products ?? {},
    });
  } catch {
    return json(401, { error: 'unauthorized' });
  }
};
