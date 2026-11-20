import { App } from "aws-cdk-lib";
import { Match, Template } from "aws-cdk-lib/assertions";
import { beforeAll, describe, expect, it } from "vitest";
import { AccountsStack, type Stage } from "../lib/stack.ts";
import { MailStack } from "../lib/mail.ts";
import config from "../cdk.json" with { type: "json" };

const env = { account: "111111111111", region: "us-east-1" };
const stages = config.context.stages as Record<Stage, { mailDomain: string; hostedZone?: string; testInbox?: boolean }>;

const synth = (stage: Stage) => {
  const app = new App();
  const mail = new MailStack(app, `ConfessionalChristianityMail-${stage}`, { env, stage, ...stages[stage] });
  const accounts = new AccountsStack(app, `ConfessionalChristianity-${stage}`, { env, stage, mailDomain: stages[stage].mailDomain });
  return { mail: Template.fromStack(mail), accounts: Template.fromStack(accounts) };
};

let dev: ReturnType<typeof synth>;
let prod: ReturnType<typeof synth>;
beforeAll(() => {
  dev = synth("dev");
  prod = synth("prod");
});

describe("user pool", () => {
  it("is on the Essentials plan, signs in by email, and allows self sign-up", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      t.hasResourceProperties("AWS::Cognito::UserPool", {
        UserPoolTier: "ESSENTIALS",
        UsernameAttributes: ["email"],
        AutoVerifiedAttributes: ["email"],
        AdminCreateUserConfig: { AllowAdminCreateUserOnly: false },
      });
    }
  });

  it("offers an emailed one-time code as a first factor (PASSWORD is mandatory in Cognito's list)", () => {
    prod.accounts.hasResourceProperties("AWS::Cognito::UserPool", {
      Policies: { SignInPolicy: { AllowedFirstAuthFactors: ["PASSWORD", "EMAIL_OTP"] } },
    });
  });

  it("has no account recovery, so ForgotPassword can't set a password", () => {
    prod.accounts.hasResourceProperties("AWS::Cognito::UserPool", {
      AccountRecoverySetting: { RecoveryMechanisms: [{ Name: "admin_only", Priority: 1 }] },
    });
  });

  it("sends email through SES (DEVELOPER) from the stage's verified domain", () => {
    const emailConfig = (t: Template) =>
      (Object.values(t.findResources("AWS::Cognito::UserPool"))[0] as { Properties: { EmailConfiguration: Record<string, unknown> } })
        .Properties.EmailConfiguration;
    const p = emailConfig(prod.accounts);
    expect(p.EmailSendingAccount).toBe("DEVELOPER");
    expect(p.From).toBe("Confessional Christianity <no-reply@confessionalchristianity.com>");
    expect(JSON.stringify(p.SourceArn)).toContain(":identity/confessionalchristianity.com");
    const d = emailConfig(dev.accounts);
    expect(d.EmailSendingAccount).toBe("DEVELOPER");
    expect(JSON.stringify(d.SourceArn)).toContain(":identity/cc-dev-mail.barbrabell.com");
  });

  it("is destroyed with dev but retained and protected in prod", () => {
    dev.accounts.hasResource("AWS::Cognito::UserPool", { DeletionPolicy: "Delete" });
    prod.accounts.hasResource("AWS::Cognito::UserPool", {
      DeletionPolicy: "Retain",
      UpdateReplacePolicy: "Retain",
      Properties: Match.objectLike({ DeletionProtection: "ACTIVE" }),
    });
  });
});

describe("app client", () => {
  it("is public and allows only choice-based sign-in and refresh: no password or SRP flows", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      t.hasResourceProperties("AWS::Cognito::UserPoolClient", {
        GenerateSecret: false,
        PreventUserExistenceErrors: "ENABLED",
        ExplicitAuthFlows: ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"],
      });
      const flows = Object.values(t.findResources("AWS::Cognito::UserPoolClient"))
        .flatMap((r) => (r as { Properties: { ExplicitAuthFlows: string[] } }).Properties.ExplicitAuthFlows);
      for (const banned of ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_CUSTOM_AUTH"]) {
        expect(flows).not.toContain(banned);
      }
    }
  });

  it("has no OAuth / hosted UI", () => {
    const client = Object.values(prod.accounts.findResources("AWS::Cognito::UserPoolClient"))[0] as { Properties: Record<string, unknown> };
    expect(client.Properties.AllowedOAuthFlows).toBeUndefined();
    expect(client.Properties.CallbackURLs).toBeUndefined();
  });

  it("keeps people signed in: the refresh token lasts ten years", () => {
    prod.accounts.hasResourceProperties("AWS::Cognito::UserPoolClient", {
      RefreshTokenValidity: 3650 * 24 * 60,
      TokenValidityUnits: Match.objectLike({ RefreshToken: "minutes" }),
    });
  });

  it("outputs what the app and the server need", () => {
    for (const name of ["Region", "UserPoolId", "AppClientId"]) prod.accounts.hasOutput(name, {});
  });
});

describe("mail", () => {
  it("verifies each stage's sending domain with Easy DKIM, and keeps prod's", () => {
    dev.mail.hasResourceProperties("AWS::SES::EmailIdentity", { EmailIdentity: "cc-dev-mail.barbrabell.com" });
    prod.mail.hasResource("AWS::SES::EmailIdentity", {
      DeletionPolicy: "Retain",
      Properties: { EmailIdentity: "confessionalchristianity.com" },
    });
  });

  it("publishes dev's DKIM and inbox records in Route 53; prod's DNS is outside AWS", () => {
    dev.mail.resourcePropertiesCountIs("AWS::Route53::RecordSet", { Type: "CNAME" }, 3);
    dev.mail.hasResourceProperties("AWS::Route53::RecordSet", {
      Type: "MX",
      Name: "cc-dev-mail.barbrabell.com.",
      ResourceRecords: ["10 inbound-smtp.us-east-1.amazonaws.com"],
    });
    // SES's DKIM token names are already fully qualified: the zone must not be appended again.
    for (const r of Object.values(dev.mail.findResources("AWS::Route53::RecordSet", { Properties: { Type: "CNAME" } }))) {
      const name = JSON.stringify((r as { Properties: { Name: unknown } }).Properties.Name);
      expect(name).not.toContain("barbrabell.com");
      expect(name).toMatch(/\."\]\]\}$/);
    }
    prod.mail.resourceCountIs("AWS::Route53::RecordSet", 0);
    prod.mail.hasOutput("DkimRecords", {});
  });

  it("gives dev an inbox agents can read (S3) and prod none", () => {
    dev.mail.hasResourceProperties("AWS::SES::ReceiptRule", {
      Rule: Match.objectLike({
        Recipients: ["cc-dev-mail.barbrabell.com"],
        Actions: [Match.objectLike({ S3Action: Match.objectLike({ ObjectKeyPrefix: "inbox/" }) })],
      }),
    });
    prod.mail.resourceCountIs("AWS::SES::ReceiptRule", 0);
    prod.mail.resourceCountIs("AWS::S3::Bucket", 0);
  });
});
