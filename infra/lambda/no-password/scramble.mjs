// TKL-850: no passwords. Cognito won't drop PASSWORD from a pool's allowed first factors, so anyone can pass a
// password to SignUp (or set one later with ChangePassword) and then sign in with USER_AUTH + PASSWORD. This
// trigger replaces the password with a random one nobody ever sees: on PostConfirmation (before the first sign-in)
// and on PreAuthentication (before every sign-in, so a password set any other way never works either).
// Throwing fails the confirmation or sign-in: better to refuse than to let a password through.
import { randomBytes, randomInt } from "node:crypto";

const LOWER = "abcdefghijklmnopqrstuvwxyz";
const UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGIT = "0123456789";
const SYMBOL = "!#$%&*+-=?@^_~";
const ALL = LOWER + UPPER + DIGIT + SYMBOL;

/** 64 random characters, with at least one of each class Cognito's password policy can require. */
export function randomPassword() {
  const chars = [...randomBytes(60)].map((b) => ALL[b % ALL.length]);
  for (const set of [LOWER, UPPER, DIGIT, SYMBOL]) chars.splice(randomInt(chars.length + 1), 0, set[randomInt(set.length)]);
  return chars.join("");
}

/** @param setPassword sends an AdminSetUserPassword request */
export const scrambleHandler = (setPassword) => async (event) => {
  await setPassword({ UserPoolId: event.userPoolId, Username: event.userName, Password: randomPassword(), Permanent: true });
  return event;
};
