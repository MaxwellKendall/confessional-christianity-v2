// TKL-889: native Sign in with Apple on the Cognito pool. Tokens here are signed with a local RSA key that stands in
// for Apple's JWKS, so every check (signature, issuer, audience, expiry, nonce, subject binding) runs for real.
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import { AUDIENCE, checkToken, ISSUER, makeVerifier } from "../lambda/apple/token.mjs";
import { answer, create, define, protectAppleEmail, reserveAppleAddress, SUBJECT } from "../lambda/apple/auth.mjs";
import { appleAddress, provision, startHandler } from "../lambda/apple/provision.mjs";

const sha256 = (v) => createHash("sha256").update(v).digest("hex");
const NOW = 1_800_000_000; // seconds
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const KEYS = [{ ...publicKey.export({ format: "jwk" }), kid: "test-key", alg: "RS256", use: "sig" }];
const other = generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function token(claims = {}, { key = privateKey, kid = "test-key", alg = "RS256" } = {}) {
  const head = b64({ alg, kid });
  const body = b64({
    iss: ISSUER, aud: AUDIENCE, sub: "001234.abcdef.0987", iat: NOW - 5, exp: NOW + 600,
    nonce: sha256("raw-nonce"), email: "a@privaterelay.appleid.com", email_verified: "true", ...claims,
  });
  return `${head}.${body}.${sign("RSA-SHA256", Buffer.from(`${head}.${body}`), key).toString("base64url")}`;
}
const check = (t) => checkToken(t, KEYS, NOW);

describe("checkToken", () => {
  it("accepts a token Apple signed for this app that hasn't expired", () => {
    expect(check(token())).toMatchObject({ ok: true, claims: { sub: "001234.abcdef.0987", nonce: sha256("raw-nonce") } });
  });
  for (const [why, t] of [
    ["audience", token({ aud: "com.maxwellkendall.aicoach" })],
    ["expired", token({ exp: NOW - 1 })],
    ["issuer", token({ iss: "https://evil.example" })],
    ["signature", token({}, { key: other })],
    ["unknown key", token({}, { kid: "rotated" })],
    ["algorithm", token({}, { alg: "none" })],
    ["subject", token({ sub: "" })],
    ["too old", token({ iat: NOW - 3600 })],
  ]) {
    it(`refuses a token with a bad ${why}`, () => expect(check(t)).toEqual({ ok: false, why }));
  }
  it("refuses garbage", () => {
    expect(check("nope").ok).toBe(false);
    expect(check("a.b.c").ok).toBe(false);
    expect(check(undefined).ok).toBe(false);
  });
});

describe("makeVerifier (Apple's JWKS)", () => {
  it("fetches the keys once, and again when a token names a key it hasn't seen", async () => {
    let ms = NOW * 1000;
    const fetchKeys = vi.fn().mockResolvedValue(KEYS);
    const verifyToken = makeVerifier(fetchKeys, () => ms);
    expect((await verifyToken(token())).ok).toBe(true);
    expect((await verifyToken(token())).ok).toBe(true);
    expect(fetchKeys).toHaveBeenCalledTimes(1);
    ms += 60_000;
    expect((await verifyToken(token({}, { kid: "rotated" }))).ok).toBe(false);
    expect(fetchKeys).toHaveBeenCalledTimes(2);
  });
  it("doesn't refetch for every unknown key: at most once every 30 s", async () => {
    let ms = NOW * 1000;
    const fetchKeys = vi.fn().mockResolvedValue(KEYS);
    const verifyToken = makeVerifier(fetchKeys, () => ms);
    await verifyToken(token({}, { kid: "x1" }));
    await verifyToken(token({}, { kid: "x2" }));
    expect(fetchKeys).toHaveBeenCalledTimes(1);
    ms += 31_000;
    await verifyToken(token({}, { kid: "x3" }));
    expect(fetchKeys).toHaveBeenCalledTimes(2);
  });
  it("fails closed when Apple's keys can't be fetched", async () => {
    const verifyToken = makeVerifier(vi.fn().mockRejectedValue(new Error("down")), () => NOW * 1000);
    await expect(verifyToken(token())).rejects.toThrow("down");
  });
});

/** An in-memory Cognito pool with email as the username attribute: it assigns its own username (a UUID). */
function fakePool() {
  const users = new Map(); // address -> { username, attributes }
  let n = 0;
  const pool = {
    users,
    get: vi.fn(async (address) => users.get(address)),
    create: vi.fn(async (address, attributes) => {
      await Promise.resolve(); // let a concurrent call interleave
      if (users.has(address)) throw Object.assign(new Error("exists"), { name: "UsernameExistsException" });
      const user = { username: `uuid-${++n}`, status: "FORCE_CHANGE_PASSWORD", attributes: { email: address, ...attributes } };
      users.set(address, user);
      return user;
    }),
    confirm: vi.fn(async (username) => {
      for (const u of users.values()) if (u.username === username) u.status = "CONFIRMED";
    }),
  };
  return pool;
}
const verifiedClaims = (claims = {}) => ({ sub: "001234.abcdef.0987", email: "a@privaterelay.appleid.com", email_verified: "true", ...claims });

describe("provision", () => {
  it("creates one Apple account the first time, under an unroutable address, and answers the pool's username", async () => {
    const pool = fakePool();
    const username = await provision(verifiedClaims(), pool);
    expect(username).toBe("uuid-1");
    expect(pool.create).toHaveBeenCalledOnce();
    const [address, attributes] = pool.create.mock.calls[0];
    expect(address).toBe(appleAddress("001234.abcdef.0987"));
    expect(address).toMatch(/^[0-9a-f]{64}@apple-signin\.invalid$/);
    expect(attributes).toEqual({
      [SUBJECT]: "001234.abcdef.0987",
      "custom:appleEmail": "a@privaterelay.appleid.com",
      "custom:appleEmailVerified": "true",
    });
    expect(pool.confirm).toHaveBeenCalledWith("uuid-1");
  });

  it("finishes confirming a user a crashed run created but left in FORCE_CHANGE_PASSWORD", async () => {
    const pool = fakePool();
    pool.confirm.mockRejectedValueOnce(new Error("throttled"));
    await expect(provision(verifiedClaims(), pool)).rejects.toThrow("throttled");
    expect(await provision(verifiedClaims(), pool)).toBe("uuid-1");
    expect(pool.create).toHaveBeenCalledOnce();
    expect([...pool.users.values()][0].status).toBe("CONFIRMED");
    await provision(verifiedClaims(), pool);
    expect(pool.confirm).toHaveBeenCalledTimes(2);
  });

  it("returns the same username on a repeat call without creating again", async () => {
    const pool = fakePool();
    const first = await provision(verifiedClaims(), pool);
    const again = await provision(verifiedClaims({ email: undefined }), pool);
    expect(again).toBe(first);
    expect(pool.create).toHaveBeenCalledOnce();
    expect(pool.users.size).toBe(1);
  });

  it("creates exactly one user when two first sign-ins race", async () => {
    const pool = fakePool();
    const [a, b] = await Promise.all([provision(verifiedClaims(), pool), provision(verifiedClaims(), pool)]);
    expect(a).toBe(b);
    expect(pool.users.size).toBe(1);
  });

  it("gives different Apple users different accounts", async () => {
    const pool = fakePool();
    expect(await provision(verifiedClaims(), pool)).not.toBe(await provision(verifiedClaims({ sub: "999.other.1" }), pool));
  });

  it("records an unverified Apple email as unverified, and no email as no metadata", async () => {
    const pool = fakePool();
    await provision(verifiedClaims({ email_verified: false }), pool);
    expect(pool.create.mock.calls[0][1]["custom:appleEmailVerified"]).toBe("false");
    await provision(verifiedClaims({ sub: "2.x.2", email: undefined }), pool);
    expect(pool.create.mock.calls[1][1]).toEqual({ [SUBJECT]: "2.x.2" });
  });

  it("never links to the email account that uses Apple's email: that one stays separate", async () => {
    const pool = fakePool();
    pool.users.set("a@privaterelay.appleid.com", { username: "email-user", attributes: { email: "a@privaterelay.appleid.com" } });
    expect(await provision(verifiedClaims(), pool)).not.toBe("email-user");
  });

  it("refuses a user at the address whose bound Apple subject doesn't match", async () => {
    const pool = fakePool();
    pool.users.set(appleAddress("001234.abcdef.0987"), { username: "squatter", attributes: {} });
    await expect(provision(verifiedClaims(), pool)).rejects.toThrow("binding");
  });
});

describe("appleStart (Function URL)", () => {
  const post = (body) => ({ requestContext: { http: { method: "POST" } }, body: JSON.stringify(body), isBase64Encoded: false });
  const deps = (pool = fakePool()) => ({ verifyToken: async (t) => checkToken(t, KEYS, NOW), pool });

  it("answers { username } for a good token, the same one each time", async () => {
    const d = deps();
    const r1 = await startHandler(d)(post({ identityToken: token() }));
    expect(r1.statusCode).toBe(200);
    expect(JSON.parse(r1.body)).toEqual({ username: "uuid-1" });
    const r2 = await startHandler(d)(post({ identityToken: token() }));
    expect(JSON.parse(r2.body)).toEqual({ username: "uuid-1" });
  });
  it("refuses a bad token with 401 and creates nobody", async () => {
    const d = deps();
    const r = await startHandler(d)(post({ identityToken: token({ aud: "someone.else" }) }));
    expect(r.statusCode).toBe(401);
    expect(d.pool.create).not.toHaveBeenCalled();
  });
  it("wants POST with JSON and a token", async () => {
    const h = startHandler(deps());
    expect((await h({ requestContext: { http: { method: "GET" } } })).statusCode).toBe(405);
    expect((await h({ requestContext: { http: { method: "POST" } }, body: "{" })).statusCode).toBe(400);
    expect((await h(post({}))).statusCode).toBe(400);
  });
  it("accepts a base64-encoded body", async () => {
    const r = await startHandler(deps())({ requestContext: { http: { method: "POST" } }, isBase64Encoded: true,
      body: Buffer.from(JSON.stringify({ identityToken: token() })).toString("base64") });
    expect(r.statusCode).toBe(200);
  });
  it("answers 503 without details when Cognito fails", async () => {
    const pool = fakePool();
    pool.get.mockRejectedValue(new Error("throttled"));
    const r = await startHandler(deps(pool))(post({ identityToken: token() }));
    expect(r.statusCode).toBe(503);
    expect(r.body).not.toContain("throttled");
  });
});

describe("custom auth triggers", () => {
  const defineEvent = (session, userNotFound = false) => ({ request: { session, userNotFound }, response: {} });

  it("define: one CUSTOM_CHALLENGE, tokens only after it passes, otherwise fail", async () => {
    expect((await define(defineEvent([]))).response).toMatchObject({ challengeName: "CUSTOM_CHALLENGE", issueTokens: false, failAuthentication: false });
    expect((await define(defineEvent([{ challengeName: "CUSTOM_CHALLENGE", challengeResult: true }]))).response)
      .toMatchObject({ issueTokens: true, failAuthentication: false });
    expect((await define(defineEvent([{ challengeName: "CUSTOM_CHALLENGE", challengeResult: false }]))).response)
      .toMatchObject({ issueTokens: false, failAuthentication: true });
    expect((await define(defineEvent([{ challengeName: "CUSTOM_CHALLENGE", challengeResult: true }], true))).response)
      .toMatchObject({ issueTokens: false, failAuthentication: true });
    expect((await define(defineEvent([{ challengeName: "PASSWORD_VERIFIER", challengeResult: true }]))).response)
      .toMatchObject({ issueTokens: false, failAuthentication: true });
  });

  it("create: a public 'apple' challenge with no secret in it", async () => {
    const e = await create({ request: {}, response: {} });
    expect(e.response.publicChallengeParameters).toEqual({ kind: "apple" });
    expect(e.response.challengeMetadata).toBe("APPLE");
  });

  const verifyEvent = (challengeAnswer, attributes = { [SUBJECT]: "001234.abcdef.0987" }) =>
    ({ userName: "uuid-1", request: { userAttributes: attributes, challengeAnswer, userNotFound: false }, response: {} });
  const verify = async (e) => (await answer(e, async (t) => checkToken(t, KEYS, NOW))).response.answerCorrect;
  const reply = (identityToken, nonce = "raw-nonce") => JSON.stringify({ identityToken, nonce });

  it("verify: a good token with its nonce signs in its own Apple user", async () => {
    expect(await verify(verifyEvent(reply(token())))).toBe(true);
  });
  it("verify: refuses a wrong audience", async () => expect(await verify(verifyEvent(reply(token({ aud: "x.y" }))))).toBe(false));
  it("verify: refuses an expired token", async () => expect(await verify(verifyEvent(reply(token({ exp: NOW - 1 }))))).toBe(false));
  it("verify: refuses the wrong nonce", async () => expect(await verify(verifyEvent(reply(token(), "another-nonce")))).toBe(false));
  it("verify: refuses a missing nonce", async () => expect(await verify(verifyEvent(JSON.stringify({ identityToken: token() })))).toBe(false));
  it("verify: refuses the hashed nonce sent back as is", async () => expect(await verify(verifyEvent(reply(token(), sha256("raw-nonce"))))).toBe(false));
  it("verify: refuses another Apple user's token", async () => {
    expect(await verify(verifyEvent(reply(token({ sub: "777.someone.else" }))))).toBe(false);
  });
  it("verify: an Apple token never signs in to an email account (no bound subject)", async () => {
    expect(await verify(verifyEvent(reply(token()), { email: "a@privaterelay.appleid.com" }))).toBe(false);
  });
  it("verify: refuses an unreadable answer without throwing", async () => {
    expect(await verify(verifyEvent("not json"))).toBe(false);
  });
  it("verify: fails closed when Apple's keys can't be fetched", async () => {
    const e = await answer(verifyEvent(reply(token())), async () => { throw new Error("down"); });
    expect(e.response.answerCorrect).toBe(false);
  });
});

describe("keeping Apple and email accounts apart", () => {
  const signUp = (email, triggerSource = "PreSignUp_SignUp") => ({ triggerSource, request: { userAttributes: { email } }, response: {} });

  it("self sign-up can't take an Apple account's address", async () => {
    await expect(reserveAppleAddress(signUp(appleAddress("1.a.1")))).rejects.toThrow();
    await expect(reserveAppleAddress(signUp(` ${appleAddress("1.a.1").toUpperCase()} `))).rejects.toThrow();
  });
  it("other sign-ups, and appleStart's admin creation, go through", async () => {
    const e = signUp("someone@example.com");
    expect(await reserveAppleAddress(e)).toBe(e);
    const admin = signUp(appleAddress("1.a.1"), "PreSignUp_AdminCreateUser");
    expect(await reserveAppleAddress(admin)).toBe(admin);
  });
  it("an Apple account can't move its sign-in to an email address (no verification code is sent)", async () => {
    for (const triggerSource of ["CustomMessage_UpdateUserAttribute", "CustomMessage_VerifyUserAttribute"]) {
      await expect(protectAppleEmail({ triggerSource, request: { userAttributes: { [SUBJECT]: "1.a.1" } }, response: {} })).rejects.toThrow();
      const email = { triggerSource, request: { userAttributes: { email: "x@example.com" } }, response: {} };
      expect(await protectAppleEmail(email)).toBe(email);
    }
  });
  it("email codes for sign-up still go out", async () => {
    const e = { triggerSource: "CustomMessage_SignUp", request: { userAttributes: { email: "x@example.com" } }, response: {} };
    expect(await protectAppleEmail(e)).toBe(e);
  });
});
