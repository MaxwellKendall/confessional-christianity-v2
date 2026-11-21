// TKL-889: Cognito custom auth for native Sign in with Apple, plus the two guards that keep Apple accounts apart from
// email-code accounts. One CUSTOM_CHALLENGE: the app answers with Apple's identity token and the raw nonce it asked
// Apple with. Verify passes only for a good token whose subject is the one bound to this Cognito user at creation
// (custom:appleSubject, immutable and not writable by the app client) and whose nonce claim is sha256(raw nonce).
import { createHash } from "node:crypto";
import { verifyToken } from "./token.mjs";

export const SUBJECT = "custom:appleSubject";
/** Apple accounts sign in under `<sha256(sub)>@apple-signin.invalid`: unique per Apple user, and no mail can reach it. */
export const RESERVED_DOMAIN = "@apple-signin.invalid";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export async function define(event) {
  const { session, userNotFound } = event.request;
  const last = session.at(-1);
  if (session.length === 0) {
    // Cognito runs the flow even for an unknown user (it doesn't reveal who exists); Verify refuses them.
    event.response.challengeName = "CUSTOM_CHALLENGE";
    event.response.issueTokens = false;
    event.response.failAuthentication = false;
  } else {
    const passed = !userNotFound && session.length === 1 && last.challengeName === "CUSTOM_CHALLENGE" && last.challengeResult === true;
    event.response.issueTokens = passed;
    event.response.failAuthentication = !passed;
  }
  return event;
}

export async function create(event) {
  event.response.publicChallengeParameters = { kind: "apple" };
  event.response.privateChallengeParameters = { kind: "apple" };
  event.response.challengeMetadata = "APPLE";
  return event;
}

/** @param {(token: unknown) => Promise<{ok: boolean, claims?: {sub: string, nonce?: unknown}}>} verify */
export async function answer(event, verify) {
  event.response.answerCorrect = false;
  const subject = event.request.userAttributes?.[SUBJECT];
  if (!subject || event.request.userNotFound) {
    console.log("refused", "not an Apple account");
    return event;
  }
  try {
    const { identityToken, nonce } = JSON.parse(event.request.challengeAnswer);
    if (typeof nonce !== "string" || !nonce || nonce.length > 1024) {
      console.log("refused", "nonce missing");
      return event;
    }
    const result = await verify(identityToken);
    if (!result.ok) console.log("refused", result.why);
    else if (result.claims.sub !== subject) console.log("refused", "another Apple user");
    else if (result.claims.nonce !== sha256(nonce)) console.log("refused", "nonce");
    else event.response.answerCorrect = true;
  } catch (e) {
    // Never log the answer: it holds Apple's token.
    console.log("refused", "unreadable answer or Apple's keys unavailable", e?.name);
  }
  return event;
}

/** Lambda calls a handler with (event, context), so the verifier can't be an optional second parameter here. */
export const verifyChallenge = (event) => answer(event, verifyToken);

/** PreSignUp: self sign-up can't claim an Apple account's address. appleStart's AdminCreateUser goes through. */
export async function reserveAppleAddress(event) {
  const email = event.request.userAttributes?.email;
  if (event.triggerSource === "PreSignUp_SignUp" && typeof email === "string" && email.trim().toLowerCase().endsWith(RESERVED_DOMAIN)) {
    throw new Error("This address is reserved.");
  }
  return event;
}

/**
 * CustomMessage: an Apple account can't change its sign-in address to a real email (which would let email codes
 * sign in to it): failing here means no verification code goes out, and the pool keeps the old email until one is
 * verified. Every other message is Cognito's default.
 */
export async function protectAppleEmail(event) {
  const source = event.triggerSource;
  if ((source === "CustomMessage_UpdateUserAttribute" || source === "CustomMessage_VerifyUserAttribute")
    && event.request.userAttributes?.[SUBJECT]) {
    throw new Error("An Apple account's email can't be changed.");
  }
  return event;
}
