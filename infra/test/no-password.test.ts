import { describe, expect, it, vi } from "vitest";
import { randomPassword, scrambleHandler } from "../lambda/no-password/scramble.mjs";

describe("randomPassword", () => {
  it("is 64 characters with every class Cognito's default policy asks for", () => {
    for (let i = 0; i < 200; i++) {
      const p = randomPassword();
      expect(p).toHaveLength(64);
      expect(p).toMatch(/[a-z]/);
      expect(p).toMatch(/[A-Z]/);
      expect(p).toMatch(/[0-9]/);
      expect(p).toMatch(/[^A-Za-z0-9]/);
    }
  });

  it("never repeats", () => {
    const seen = new Set(Array.from({ length: 500 }, () => randomPassword()));
    expect(seen.size).toBe(500);
  });
});

describe("scrambleHandler", () => {
  const event = (triggerSource: string) => ({
    triggerSource,
    userPoolId: "us-east-1_Pool",
    userName: "0b1c-sub",
    request: { userAttributes: { email: "a@example.com" } },
    response: {},
  });

  for (const source of ["PostConfirmation_ConfirmSignUp", "PreAuthentication_Authentication"]) {
    it(`replaces the password with an unknown permanent one on ${source}, and returns the event`, async () => {
      const setPassword = vi.fn().mockResolvedValue({});
      const e = event(source);
      await expect(scrambleHandler(setPassword)(e)).resolves.toBe(e);
      expect(setPassword).toHaveBeenCalledOnce();
      const input = setPassword.mock.calls[0][0];
      expect(input).toMatchObject({ UserPoolId: "us-east-1_Pool", Username: "0b1c-sub", Permanent: true });
      expect(input.Password).toHaveLength(64);
    });
  }

  it("uses a new password every time", async () => {
    const setPassword = vi.fn().mockResolvedValue({});
    const h = scrambleHandler(setPassword);
    await h(event("PreAuthentication_Authentication"));
    await h(event("PreAuthentication_Authentication"));
    expect(setPassword.mock.calls[0][0].Password).not.toBe(setPassword.mock.calls[1][0].Password);
  });

  it("fails the sign-in (throws) when the password can't be replaced, rather than letting it through", async () => {
    const setPassword = vi.fn().mockRejectedValue(new Error("AccessDenied"));
    await expect(scrambleHandler(setPassword)(event("PreAuthentication_Authentication"))).rejects.toThrow("AccessDenied");
  });
});
