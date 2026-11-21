// TKL-889: Apple's identity token from the app's native Sign in with Apple sheet. Trusted when Apple signed it
// (RS256, a key from Apple's JWKS), it's for this app (audience = the bundle id), it hasn't expired and it's fresh.
// The nonce is checked by the custom auth Verify trigger (auth.mjs), which has the raw nonce.
import { createPublicKey, verify } from "node:crypto";

export const ISSUER = "https://appleid.apple.com";
export const AUDIENCE = "com.confessionalchristianity.app";
/** Sign-in takes seconds: a token issued longer ago than this is refused even before Apple's own expiry. */
const MAX_AGE_SECONDS = 10 * 60;
/** Clock skew allowed for a token that says it was issued in the future. */
const SKEW_SECONDS = 60;

/**
 * @param {unknown} token the compact JWT
 * @param {Array<{kid: string}>} keys Apple's public keys (JWKs)
 * @param {number} now seconds since the epoch
 * @returns {{ok: true, claims: Record<string, unknown> & {sub: string}} | {ok: false, why: string}}
 */
export function checkToken(token, keys, now) {
  if (typeof token !== "string" || token.length > 16_384) return { ok: false, why: "not a JWT" };
  const parts = token.split(".");
  if (parts.length !== 3) return { ok: false, why: "not a JWT" };
  const [head, body, signature] = parts;
  let header, claims;
  try {
    header = JSON.parse(Buffer.from(head, "base64url").toString());
    claims = JSON.parse(Buffer.from(body, "base64url").toString());
  } catch {
    return { ok: false, why: "not JSON" };
  }
  if (header?.alg !== "RS256") return { ok: false, why: "algorithm" };
  const jwk = keys.find((k) => k.kid === header.kid && k.kty === "RSA");
  if (!jwk) return { ok: false, why: "unknown key" };
  let signed = false;
  try {
    signed = verify("RSA-SHA256", Buffer.from(`${head}.${body}`), createPublicKey({ key: jwk, format: "jwk" }),
      Buffer.from(signature, "base64url"));
  } catch {
    signed = false;
  }
  if (!signed) return { ok: false, why: "signature" };
  if (claims?.iss !== ISSUER) return { ok: false, why: "issuer" };
  if (claims.aud !== AUDIENCE) return { ok: false, why: "audience" };
  if (!(Number.isFinite(claims.exp) && claims.exp > now)) return { ok: false, why: "expired" };
  if (!(Number.isFinite(claims.iat) && now - claims.iat <= MAX_AGE_SECONDS && claims.iat - now <= SKEW_SECONDS)) {
    return { ok: false, why: "too old" };
  }
  if (typeof claims.sub !== "string" || !claims.sub || claims.sub.length > 255) return { ok: false, why: "subject" };
  return { ok: true, claims };
}

/**
 * A verifier with Apple's keys cached. It fetches them again when a token names a key it hasn't seen (Apple rotates
 * them), but at most once every 30 s, so a public endpoint fed made-up key ids can't hammer Apple.
 * @param {() => Promise<Array<{kid: string}>>} fetchKeys
 * @param {() => number} nowMs
 */
export function makeVerifier(fetchKeys, nowMs = Date.now) {
  let keys = [];
  let fetchedAt = -Infinity;
  let pending;
  const refresh = () => {
    fetchedAt = nowMs();
    pending ??= fetchKeys().then((next) => { keys = next; }).finally(() => { pending = undefined; });
    return pending;
  };
  return async (token) => {
    if (!keys.length) await refresh();
    let result = checkToken(token, keys, nowMs() / 1000);
    if (!result.ok && result.why === "unknown key" && nowMs() - fetchedAt >= 30_000) {
      await refresh();
      result = checkToken(token, keys, nowMs() / 1000);
    }
    return result;
  };
}

export async function fetchAppleKeys() {
  const response = await fetch(`${ISSUER}/auth/keys`, { signal: AbortSignal.timeout(2500), redirect: "error" });
  if (!response.ok) throw new Error(`Apple's keys: ${response.status}`);
  const { keys } = await response.json();
  if (!Array.isArray(keys) || !keys.length) throw new Error("Apple's keys: empty");
  return keys;
}

export const verifyToken = makeVerifier(fetchAppleKeys);
