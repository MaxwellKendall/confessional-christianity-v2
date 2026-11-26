// @studio/auth: server-side checks for tokens from the studio pool (StudioIdentity-<stage>).
// verify() proves a token is genuine, unexpired and issued to *this* product's app client;
// access() reads that product's plan from the products: {slug: plan} claim the pre-token trigger adds.
import { CognitoJwtVerifier } from "aws-jwt-verify";
import type { Jwks } from "aws-jwt-verify/jwk";

export interface VerifyOptions {
  /** Defaults to STUDIO_USER_POOL_ID. */
  userPoolId?: string;
  /** Use these keys instead of fetching the pool's JWKS (tests, offline). */
  jwks?: Jwks;
}
export interface AccessOptions extends VerifyOptions {
  /** This product's app client ID. Defaults to STUDIO_CLIENT_ID. */
  clientId?: string;
}
export interface StudioClaims {
  sub: string;
  token_use: "id" | "access";
  products?: Record<string, string>;
  [claim: string]: unknown;
}

const verifiers = new Map<string, ReturnType<typeof makeVerifier>>();
function makeVerifier(userPoolId: string, clientId: string, jwks?: Jwks) {
  const v = CognitoJwtVerifier.create({ userPoolId, clientId, tokenUse: null });
  if (jwks) v.cacheJwks(jwks);
  return v;
}

/** Verifies an ID or access token for clientId; throws if it's forged, expired, from another pool or another client. */
export async function verify(token: string, clientId: string, opts: VerifyOptions = {}): Promise<StudioClaims> {
  const userPoolId = opts.userPoolId ?? process.env.STUDIO_USER_POOL_ID;
  if (!userPoolId) throw new Error("verify: no userPoolId (pass it or set STUDIO_USER_POOL_ID)");
  if (!clientId) throw new Error("verify: no clientId");
  let v = opts.jwks ? undefined : verifiers.get(`${userPoolId}/${clientId}`);
  if (!v) {
    v = makeVerifier(userPoolId, clientId, opts.jwks);
    if (!opts.jwks) verifiers.set(`${userPoolId}/${clientId}`, v);
  }
  return (await v.verify(token)) as unknown as StudioClaims;
}

/** The user's plan for product (e.g. "plus"), or null without access. Verifies the token first. */
export async function access(token: string, product: string, opts: AccessOptions = {}): Promise<string | null> {
  const clientId = opts.clientId ?? process.env.STUDIO_CLIENT_ID;
  if (!clientId) throw new Error("access: no clientId (pass it or set STUDIO_CLIENT_ID)");
  const claims = await verify(token, clientId, opts);
  const plan = claims.products?.[product];
  return typeof plan === "string" ? plan : null;
}
