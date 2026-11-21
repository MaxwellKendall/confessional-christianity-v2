import { createPrivateKey, sign } from "node:crypto";

const apple = "https://appleid.apple.com";
const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");

export type AppleRevokeConfig = {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKey: string;
};

function clientSecret(config: AppleRevokeConfig): string {
  const now = Math.floor(Date.now() / 1000);
  const header = encode({ alg: "ES256", kid: config.keyId });
  const payload = encode({ iss: config.teamId, iat: now, exp: now + 300, aud: apple, sub: config.clientId });
  const input = `${header}.${payload}`;
  const key = createPrivateKey(config.privateKey.replace(/\\n/g, "\n"));
  const signature = sign("sha256", Buffer.from(input), { key, dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

export async function revokeAppleTokens(config: AppleRevokeConfig, code: string): Promise<void> {
  const base = { client_id: config.clientId, client_secret: clientSecret(config) };
  const post = (path: string, params: Record<string, string>) => fetch(`${apple}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ ...base, ...params }).toString(),
    signal: AbortSignal.timeout(5_000),
  });

  const exchange = await post("/auth/token", { code, grant_type: "authorization_code" });
  if (!exchange.ok) throw new Error("Apple token exchange failed");
  const { refresh_token: token } = await exchange.json() as { refresh_token?: string };
  if (typeof token !== "string" || !token) throw new Error("Apple returned no refresh token");
  const revoke = await post("/auth/revoke", { token, token_type_hint: "refresh_token" });
  if (!revoke.ok) throw new Error("Apple revoke failed");
}
