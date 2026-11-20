// Writes ios/App/Resources/amplify_outputs.{stage}.json (Amplify Swift's config format) and prints the
// server's settings. The IDs aren't secrets, so the file is committed.
import { mkdirSync, writeFileSync } from "node:fs";
import { stackOutputs } from "./stack.ts";

const stage = process.argv[2] ?? "dev";
if (stage !== "dev" && stage !== "prod") throw new Error(`Unknown stage "${stage}": use dev or prod`);
const out = await stackOutputs(`ConfessionalChristianity-${stage}`);

// Sign-in is passwordless (USER_AUTH with EMAIL_OTP): no OAuth domain, no password policy for the app.
const config = {
  version: "1.4",
  auth: {
    aws_region: out.Region,
    user_pool_id: out.UserPoolId,
    user_pool_client_id: out.AppClientId,
    standard_required_attributes: ["email"],
    username_attributes: ["email"],
    user_verification_types: ["email"],
    unauthenticated_identities_enabled: false,
    mfa_configuration: "NONE",
    mfa_methods: [],
  },
};

const dir = new URL("../../ios/App/Resources/", import.meta.url);
mkdirSync(dir, { recursive: true });
const path = new URL(`amplify_outputs.${stage}.json`, dir);
writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
console.log(`Wrote ${path.pathname} for ConfessionalChristianity-${stage}`);
console.log(`Server settings: COGNITO_USER_POOL_ID=${out.UserPoolId} COGNITO_CLIENT_ID=${out.AppClientId}`);
