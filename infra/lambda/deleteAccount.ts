import { AdminDeleteUserCommand, CognitoIdentityProviderClient } from "@aws-sdk/client-cognito-identity-provider";
import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";
import { CognitoJwtVerifier } from "aws-jwt-verify";
import { revokeAppleTokens, type AppleRevokeConfig } from "./appleRevoke.ts";

type Config = { userPoolId: string; clientId: string; appleSecretId: string };
type Request = {
  headers: Record<string, string | undefined>;
  requestContext: { http: { method: string } };
  body?: string;
  isBase64Encoded?: boolean;
};

const json = (statusCode: number, body: object) => ({
  statusCode,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
  body: JSON.stringify(body),
});

function appleCode(event: Request): string | undefined {
  try {
    const body = event.isBase64Encoded ? Buffer.from(event.body ?? "", "base64").toString("utf8") : event.body;
    const code: unknown = JSON.parse(body ?? "{}")?.appleAuthorizationCode;
    if (typeof code === "string" && code.trim()) return code.trim();
  } catch {
    return undefined;
  }
}

async function appleConfig(secrets: SecretsManagerClient, secretId: string): Promise<AppleRevokeConfig | null> {
  try {
    const { SecretString } = await secrets.send(new GetSecretValueCommand({ SecretId: secretId }));
    const config = JSON.parse(SecretString ?? "{}") as AppleRevokeConfig;
    for (const key of ["teamId", "keyId", "clientId", "privateKey"] as const) {
      if (typeof config[key] !== "string" || !config[key].trim()) throw new Error("Incomplete Apple configuration");
    }
    return config;
  } catch (error) {
    if (error instanceof Error && error.name === "ResourceNotFoundException") return null;
    throw error;
  }
}

export function createHandler(
  { userPoolId, clientId, appleSecretId }: Config,
  // The account-data stack will provide its idempotent cleanup here, keyed by Cognito sub.
  deleteAccountData: (subject: string) => Promise<void> = async () => {},
) {
  const verifier = CognitoJwtVerifier.create({ userPoolId, clientId, tokenUse: "access" });
  const cognito = new CognitoIdentityProviderClient();
  const secrets = new SecretsManagerClient();

  return async (event: Request) => {
    if (event.requestContext.http.method !== "POST") {
      const response = json(405, { error: "method_not_allowed" });
      return { ...response, headers: { ...response.headers, allow: "POST" } };
    }
    const authorization = Object.entries(event.headers).find(([name]) => name.toLowerCase() === "authorization")?.[1];
    const token = /^Bearer\s+(\S+)$/i.exec(authorization ?? "")?.[1];
    if (!token) return json(401, { error: "unauthorized" });

    let identity;
    try {
      identity = await verifier.verify(token);
      if (!identity.username || !identity.sub) return json(401, { error: "unauthorized" });
    } catch {
      return json(401, { error: "unauthorized" });
    }

    if (identity.username.startsWith("apple_")) {
      try {
        const config = await appleConfig(secrets, appleSecretId);
        if (config) {
          const code = appleCode(event);
          if (!code) return json(400, { error: "apple_credential_required" });
          await revokeAppleTokens(config, code);
        } else {
          console.info("[deleteAccount] Apple revoke skipped because the stage secret is absent");
        }
      } catch {
        console.warn("[deleteAccount] Apple revocation failed");
        return json(502, { error: "apple_revoke_failed" });
      }
    }

    try {
      await deleteAccountData(identity.sub);
      await cognito.send(new AdminDeleteUserCommand({ UserPoolId: userPoolId, Username: identity.username }));
      return json(200, { deleted: true });
    } catch {
      console.error("[deleteAccount] Account deletion failed");
      return json(500, { error: "delete_failed" });
    }
  };
}

let run: ReturnType<typeof createHandler> | undefined;
export const handler = (event: Request) => {
  run ??= createHandler({
    userPoolId: process.env.USER_POOL_ID!,
    clientId: process.env.APP_CLIENT_ID!,
    appleSecretId: process.env.APPLE_SECRET_ID!,
  });
  return run(event);
};
