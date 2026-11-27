// Writes ios/App/Resources/amplify_outputs.{stage}.json (Amplify Swift's config format) and prints the
// server's settings. The IDs aren't secrets, so the file is committed.
// For prod, auth comes from StudioIdentity-prod (confessional client) and account_sync_url from
// ConfessionalChristianity-prod (TKL-1041, TKL-1071). For dev, Debug still uses ConfessionalChristianity-dev
// until TKL-965 moves Debug onto Studio-dev.
import { mkdirSync, writeFileSync } from "node:fs";
import { stackOutputs } from "./stack.ts";

const stage = process.argv[2] ?? "dev";
if (stage !== "dev" && stage !== "prod") throw new Error(`Unknown stage "${stage}": use dev or prod`);
const out = await stackOutputs(`ConfessionalChristianity-${stage}`);

let region = out.Region;
let userPoolId = out.UserPoolId;
let clientId = out.AppClientId;
const custom: Record<string, string> = {};

if (stage === "prod") {
  const studio = await stackOutputs("StudioIdentity-prod");
  region = studio.Region;
  userPoolId = studio.UserPoolId;
  clientId = studio.ClientIdConfessional;
  if (!userPoolId || !clientId) throw new Error("StudioIdentity-prod is missing UserPoolId or ClientIdConfessional");
  if (!out.AccountSyncUrl) throw new Error("ConfessionalChristianity-prod is missing AccountSyncUrl");
  custom.account_sync_url = out.AccountSyncUrl;
} else {
  if (out.AppleStartUrl) custom.apple_start_url = out.AppleStartUrl;
  if (out.AccountSyncUrl) custom.account_sync_url = out.AccountSyncUrl;
}

// Sign-in is passwordless (USER_AUTH with EMAIL_OTP): no OAuth domain, no password policy for the app.
const config = {
  version: "1.4",
  auth: {
    aws_region: region,
    user_pool_id: userPoolId,
    user_pool_client_id: clientId,
    standard_required_attributes: ["email"],
    username_attributes: ["email"],
    user_verification_types: ["email"],
    unauthenticated_identities_enabled: false,
    mfa_configuration: "NONE",
    mfa_methods: [],
  },
  // TKL-889 / TKL-1068 / TKL-1071: native Sign in with Apple and account sync URLs (Amplify's schema keeps app data in "custom").
  ...(Object.keys(custom).length ? { custom } : {}),
};

const dir = new URL("../../ios/App/Resources/", import.meta.url);
mkdirSync(dir, { recursive: true });
const path = new URL(`amplify_outputs.${stage}.json`, dir);
writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
console.log(`Wrote ${path.pathname} for ${stage === "prod" ? "StudioIdentity-prod + ConfessionalChristianity-prod" : `ConfessionalChristianity-${stage}`}`);
console.log(`Server settings: COGNITO_USER_POOL_ID=${userPoolId} COGNITO_CLIENT_ID=${clientId}`);
