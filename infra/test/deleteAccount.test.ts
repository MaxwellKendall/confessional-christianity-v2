import { generateKeyPairSync } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  verify: vi.fn(), create: vi.fn(),
  cognito: vi.fn(), secrets: vi.fn(), fetch: vi.fn(),
}));
vi.mock("aws-jwt-verify", () => ({
  CognitoJwtVerifier: { create: mocks.create.mockReturnValue({ verify: mocks.verify }) },
}));
vi.mock("@aws-sdk/client-cognito-identity-provider", () => ({
  CognitoIdentityProviderClient: class { send = mocks.cognito; },
  AdminDeleteUserCommand: class { constructor(readonly input: unknown) {} },
}));
vi.mock("@aws-sdk/client-secrets-manager", () => ({
  SecretsManagerClient: class { send = mocks.secrets; },
  GetSecretValueCommand: class { constructor(readonly input: unknown) {} },
}));

const privateKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey
  .export({ format: "pem", type: "pkcs8" });
const appleSecret = JSON.stringify({ teamId: "team", keyId: "key", clientId: "client", privateKey });
const pool = "us-east-1_test";
const secretId = "confessional/dev/apple-signin";
const request = (body?: string) => ({
  headers: { authorization: "Bearer token" },
  requestContext: { http: { method: "POST" } },
  body,
});

const setup = async () => {
  const { createHandler } = await import("../lambda/deleteAccount.ts");
  const deleteAccountData = vi.fn().mockResolvedValue(undefined);
  return { handler: createHandler({ userPoolId: pool, clientId: "ios", appleSecretId: secretId }, deleteAccountData), deleteAccountData };
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.verify.mockResolvedValue({ username: "caller", sub: "caller-sub" });
  mocks.cognito.mockResolvedValue({});
  mocks.secrets.mockResolvedValue({ SecretString: appleSecret });
  mocks.fetch.mockImplementation(async (url: string) => url.endsWith("/token")
    ? Response.json({ refresh_token: "refresh" })
    : new Response(null, { status: 200 }));
  vi.stubGlobal("fetch", mocks.fetch);
});

describe("deleteAccount", () => {
  it("checks access tokens for the stage pool and iOS client and rejects missing or invalid credentials", async () => {
    const { handler, deleteAccountData } = await setup();
    expect(mocks.create).toHaveBeenCalledWith({ userPoolId: pool, clientId: "ios", tokenUse: "access" });
    expect((await handler({ ...request(), headers: {} })).statusCode).toBe(401);
    mocks.verify.mockRejectedValueOnce(new Error("wrong client"));
    expect((await handler(request())).statusCode).toBe(401);
    expect(mocks.cognito).not.toHaveBeenCalled();
    expect(deleteAccountData).not.toHaveBeenCalled();
  });

  it("deletes only the token owner, including their account data, even if the body names someone else", async () => {
    const { handler, deleteAccountData } = await setup();
    const response = await handler(request(JSON.stringify({ username: "another-user" })));
    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body)).toEqual({ deleted: true });
    expect(deleteAccountData).toHaveBeenCalledWith("caller-sub");
    expect(mocks.cognito).toHaveBeenCalledWith(expect.objectContaining({ input: { UserPoolId: pool, Username: "caller" } }));
    expect(mocks.secrets).not.toHaveBeenCalled();
  });

  it("does not delete the Cognito identity if account data cleanup fails", async () => {
    const { handler, deleteAccountData } = await setup();
    deleteAccountData.mockRejectedValueOnce(new Error("unavailable"));
    expect((await handler(request())).statusCode).toBe(500);
    expect(mocks.cognito).not.toHaveBeenCalled();
  });

  it("does not perform deletion on GET", async () => {
    const { handler } = await setup();
    expect((await handler({ ...request(), requestContext: { http: { method: "GET" } } })).statusCode).toBe(405);
    expect(mocks.cognito).not.toHaveBeenCalled();
  });

  describe("Apple accounts", () => {
    beforeEach(() => mocks.verify.mockResolvedValue({ username: "apple_subject", sub: "caller-sub" }));

    it("requires an authorization code when the secret exists", async () => {
      const { handler, deleteAccountData } = await setup();
      const response = await handler(request(JSON.stringify({ appleRefreshToken: "refresh" })));
      expect(response.statusCode).toBe(400);
      expect(JSON.parse(response.body)).toEqual({ error: "apple_credential_required" });
      expect(mocks.cognito).not.toHaveBeenCalled();
      expect(deleteAccountData).not.toHaveBeenCalled();
    });

    it.each(["/token", "/revoke"])("keeps the account when Apple %s fails", async (path) => {
      mocks.fetch.mockImplementation(async (url: string) => url.endsWith(path)
        ? new Response(null, { status: 400 })
        : Response.json({ refresh_token: "refresh" }));
      const { handler, deleteAccountData } = await setup();
      const response = await handler(request(JSON.stringify({ appleAuthorizationCode: "code" })));
      expect(response.statusCode).toBe(502);
      expect(JSON.parse(response.body)).toEqual({ error: "apple_revoke_failed" });
      expect(mocks.cognito).not.toHaveBeenCalled();
      expect(deleteAccountData).not.toHaveBeenCalled();
    });

    it("keeps the account when Secrets Manager fails for a reason other than absence", async () => {
      mocks.secrets.mockRejectedValueOnce(Object.assign(new Error(), { name: "AccessDeniedException" }));
      const { handler, deleteAccountData } = await setup();
      expect((await handler(request())).statusCode).toBe(502);
      expect(deleteAccountData).not.toHaveBeenCalled();
      expect(mocks.cognito).not.toHaveBeenCalled();
    });

    it("exchanges the code and revokes the refresh token before deleting", async () => {
      const { handler } = await setup();
      const body = Buffer.from(JSON.stringify({ appleAuthorizationCode: "code" })).toString("base64");
      expect((await handler({ ...request(body), isBase64Encoded: true })).statusCode).toBe(200);
      expect(mocks.secrets).toHaveBeenCalledWith(expect.objectContaining({ input: { SecretId: secretId } }));
      expect(mocks.fetch.mock.calls.map(([url]) => url)).toEqual([
        "https://appleid.apple.com/auth/token", "https://appleid.apple.com/auth/revoke",
      ]);
      expect(new URLSearchParams(mocks.fetch.mock.calls[0][1].body).get("code")).toBe("code");
      expect(new URLSearchParams(mocks.fetch.mock.calls[1][1].body).get("token")).toBe("refresh");
      expect(mocks.fetch.mock.invocationCallOrder[1]).toBeLessThan(mocks.cognito.mock.invocationCallOrder[0]);
    });

    it("logs a skip and deletes when the stage secret does not exist", async () => {
      mocks.secrets.mockRejectedValueOnce(Object.assign(new Error(), { name: "ResourceNotFoundException" }));
      const log = vi.spyOn(console, "info").mockImplementation(() => {});
      try {
        const { handler } = await setup();
        expect((await handler(request())).statusCode).toBe(200);
        expect(log).toHaveBeenCalledWith(expect.stringMatching(/revoke skipped/i));
        expect(mocks.fetch).not.toHaveBeenCalled();
        expect(mocks.cognito).toHaveBeenCalledOnce();
      } finally {
        log.mockRestore();
      }
    });
  });
});
