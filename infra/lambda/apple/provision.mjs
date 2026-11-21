// TKL-889: appleStart's logic. Custom auth can only sign in a user who exists, so the app first posts Apple's identity
// token here and gets back the Cognito username to sign in as: the one the pool assigned to this Apple user's
// account, which is created the first time. The pool signs in by email, so the account gets a stable, unroutable
// address of its own; Apple's email is kept only as metadata. An email-code account with the same email stays a
// separate user (no automatic linking).
import { createHash } from "node:crypto";
import { RESERVED_DOMAIN, SUBJECT } from "./auth.mjs";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export const appleAddress = (sub) => sha256(sub) + RESERVED_DOMAIN;

/**
 * @typedef {{username: string, status?: string, attributes: Record<string, string>}} PoolUser
 * @typedef {{
 *   get(address: string): Promise<PoolUser | undefined>,
 *   create(address: string, attributes: Record<string, string>): Promise<PoolUser>,
 *   confirm(username: string): Promise<void>,
 * }} Pool
 * @param {{sub: string, email?: unknown, email_verified?: unknown}} claims a verified token's claims
 * @param {Pool} pool
 */
export async function provision(claims, pool) {
  const address = appleAddress(claims.sub);
  let user = await pool.get(address);
  if (!user) {
    const attributes = { [SUBJECT]: claims.sub };
    if (typeof claims.email === "string" && claims.email) {
      attributes["custom:appleEmail"] = claims.email.slice(0, 2048);
      attributes["custom:appleEmailVerified"] = String(claims.email_verified === true || claims.email_verified === "true");
    }
    try {
      user = await pool.create(address, attributes);
    } catch (e) {
      // Two first sign-ins at once: the other one made the user.
      if (e?.name !== "UsernameExistsException") throw e;
      user = await pool.get(address);
    }
  }
  if (!user?.username || user.attributes?.[SUBJECT] !== claims.sub) throw new Error("Apple account binding failed");
  // Out of FORCE_CHANGE_PASSWORD, so custom auth issues tokens instead of asking for a new password. Checked on every
  // call, so a run that created the user but failed here is finished by the next one.
  if (user.status === "FORCE_CHANGE_PASSWORD") await pool.confirm(user.username);
  return user.username;
}

const reply = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
  body: JSON.stringify(body),
});

/** @param {{verifyToken: (t: unknown) => Promise<{ok: boolean, why?: string, claims?: any}>, pool: Pool}} deps */
export const startHandler = ({ verifyToken, pool }) => async (event) => {
  if (event.requestContext?.http?.method !== "POST") return reply(405, { error: "POST" });
  let input;
  try {
    const body = event.isBase64Encoded ? Buffer.from(event.body ?? "", "base64").toString() : event.body ?? "";
    if (body.length > 20_000) return reply(400, { error: "Too large" });
    input = JSON.parse(body);
  } catch {
    return reply(400, { error: "JSON" });
  }
  if (typeof input?.identityToken !== "string" || !input.identityToken) return reply(400, { error: "identityToken" });
  try {
    const result = await verifyToken(input.identityToken);
    if (!result.ok) {
      console.log("refused", result.why);
      return reply(401, { error: "Apple's token wasn't accepted." });
    }
    return reply(200, { username: await provision(result.claims, pool) });
  } catch (e) {
    console.error("appleStart failed", e?.name, e?.message);
    return reply(503, { error: "Sign-in is unavailable. Try again." });
  }
};
