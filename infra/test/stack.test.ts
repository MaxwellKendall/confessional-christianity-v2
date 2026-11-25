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

  it("replaces any password with an unknown one on confirmation and before every sign-in", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      const pool = Object.values(t.findResources("AWS::Cognito::UserPool"))[0] as { Properties: { LambdaConfig?: Record<string, unknown> } };
      const cfg = pool.Properties.LambdaConfig ?? {};
      expect(cfg.PostConfirmation).toBeDefined();
      expect(cfg.PreAuthentication).toBeDefined();
      expect(JSON.stringify(cfg.PostConfirmation)).toBe(JSON.stringify(cfg.PreAuthentication));
      t.hasResourceProperties("AWS::Lambda::Function", { Handler: "index.handler", Runtime: "nodejs22.x" });
    }
  });

  it("lets that function set passwords only in its own pool", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      const statements = Object.values(t.findResources("AWS::IAM::Policy"))
        .flatMap((r) => (r as { Properties: { PolicyDocument: { Statement: Record<string, unknown>[] } } }).Properties.PolicyDocument.Statement);
      const set = statements.filter((s) => JSON.stringify(s.Action).includes("cognito-idp"));
      // NoPassword sets passwords; appleStart (TKL-889) finds, creates and confirms Apple users. Nothing else.
      expect(set.map((s) => s.Action)).toEqual(expect.arrayContaining([
        "cognito-idp:AdminSetUserPassword",
        ["cognito-idp:AdminGetUser", "cognito-idp:AdminCreateUser", "cognito-idp:AdminSetUserPassword"],
      ]));
      expect(set).toHaveLength(2);
      const userPoolLogicalId = Object.keys(t.findResources("AWS::Cognito::UserPool"))[0];
      for (const s of set) expect(s.Resource).toEqual({ "Fn::GetAtt": [userPoolLogicalId, "Arn"] });
    }
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
  it("is public and allows only choice-based sign-in, Apple's custom auth and refresh: no password or SRP flows", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      t.hasResourceProperties("AWS::Cognito::UserPoolClient", {
        GenerateSecret: false,
        PreventUserExistenceErrors: "ENABLED",
        ExplicitAuthFlows: ["ALLOW_USER_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"],
      });
      const flows = Object.values(t.findResources("AWS::Cognito::UserPoolClient"))
        .flatMap((r) => (r as { Properties: { ExplicitAuthFlows: string[] } }).Properties.ExplicitAuthFlows);
      for (const banned of ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH"]) {
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
    for (const name of ["Region", "UserPoolId", "AppClientId", "AppleStartUrl"]) prod.accounts.hasOutput(name, {});
  });

  it("can write only the email: nobody can set an Apple subject on themselves", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      t.hasResourceProperties("AWS::Cognito::UserPoolClient", { WriteAttributes: ["email"] });
    }
  });
});

describe("native Sign in with Apple (TKL-889)", () => {
  type Pool = { Properties: { LambdaConfig: Record<string, unknown>; Schema: Record<string, unknown>[] } };
  const pool = (t: Template) => Object.values(t.findResources("AWS::Cognito::UserPool"))[0] as Pool;
  const functionFor = (t: Template, arn: unknown) => {
    const id = (arn as { "Fn::GetAtt": [string, string] })["Fn::GetAtt"][0];
    return (t.findResources("AWS::Lambda::Function")[id] as { Properties: { Handler: string } }).Properties.Handler;
  };

  it("binds an immutable Apple subject, and keeps Apple's email and its verification as immutable metadata", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      const schema = pool(t).Properties.Schema;
      // These already exist in dev: Cognito can never remove or change a custom attribute, so they must stay exactly so.
      expect(schema).toEqual(expect.arrayContaining([
        { Name: "appleSubject", AttributeDataType: "String", Mutable: false, StringAttributeConstraints: { MaxLength: "255" } },
        { Name: "appleEmail", AttributeDataType: "String", Mutable: false, StringAttributeConstraints: { MaxLength: "2048" } },
        { Name: "appleEmailVerified", AttributeDataType: "String", Mutable: false, StringAttributeConstraints: { MaxLength: "5" } },
      ]));
    }
  });

  it("wires the custom auth triggers, the reserved-address sign-up guard and the email guard", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      const cfg = pool(t).Properties.LambdaConfig;
      expect(functionFor(t, cfg.DefineAuthChallenge)).toBe("auth.define");
      expect(functionFor(t, cfg.CreateAuthChallenge)).toBe("auth.create");
      expect(functionFor(t, cfg.VerifyAuthChallengeResponse)).toBe("auth.verifyChallenge");
      expect(functionFor(t, cfg.PreSignUp)).toBe("auth.reserveAppleAddress");
      expect(functionFor(t, cfg.CustomMessage)).toBe("auth.protectAppleEmail");
      // Email OTP's password scrambler stays.
      expect(functionFor(t, cfg.PreAuthentication)).toBe("index.handler");
    }
  });

  it("serves appleStart on a public Function URL that knows its pool", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      const fns = t.findResources("AWS::Lambda::Function", { Properties: { Handler: "start.handler" } });
      const [id] = Object.keys(fns);
      expect(Object.keys(fns)).toHaveLength(1);
      const poolId = Object.keys(t.findResources("AWS::Cognito::UserPool"))[0];
      t.hasResourceProperties("AWS::Lambda::Function", {
        Handler: "start.handler",
        Runtime: "nodejs22.x",
        Environment: { Variables: { USER_POOL_ID: { Ref: poolId } } },
      });
      t.hasResourceProperties("AWS::Lambda::Url", { AuthType: "NONE", TargetFunctionArn: { "Fn::GetAtt": [id, "Arn"] } });
      t.hasOutput("AppleStartUrl", { Value: Match.objectLike({ "Fn::GetAtt": [Match.stringLikeRegexp("^AppleStartFunctionUrl"), "FunctionUrl"] }) });
    }
  });

  it("keeps the original email until a new one is verified", () => {
    for (const t of [dev.accounts, prod.accounts]) {
      t.hasResourceProperties("AWS::Cognito::UserPool", { UserAttributeUpdateSettings: { AttributesRequireVerificationBeforeUpdate: ["email"] } });
    }
  });

  it("adds no hosted-UI Apple identity provider", () => {
    for (const t of [dev.accounts, prod.accounts]) t.resourceCountIs("AWS::Cognito::UserPoolIdentityProvider", 0);
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

describe("account sync", () => {
  it("uses only the stage user pool and exposes push and pull on a private table", () => {
    for (const { accounts } of [dev, prod]) {
      const pool = Object.keys(accounts.findResources("AWS::Cognito::UserPool"))[0];
      accounts.hasResourceProperties("AWS::AppSync::GraphQLApi", {
        AuthenticationType: "AMAZON_COGNITO_USER_POOLS",
        UserPoolConfig: { UserPoolId: { Ref: pool }, DefaultAction: "ALLOW" },
        AdditionalAuthenticationProviders: Match.absent(),
      });
      accounts.hasResourceProperties("AWS::DynamoDB::Table", {
        KeySchema: [{ AttributeName: "pk", KeyType: "HASH" }, { AttributeName: "sk", KeyType: "RANGE" }],
      });
      accounts.hasResourceProperties("AWS::AppSync::Resolver", { TypeName: "Mutation", FieldName: "pushSync" });
      accounts.hasResourceProperties("AWS::AppSync::Resolver", { TypeName: "Query", FieldName: "pullSync" });
      const schemas = Object.values(accounts.findResources("AWS::AppSync::GraphQLSchema"));
      expect(schemas).toHaveLength(1);
      const definition = (schemas[0] as { Properties: { Definition: string } }).Properties.Definition;
      expect(definition).toContain("pushSync(changes: [SyncChangeInput!]!): [SyncPushResult!]!");
      expect(definition).toContain("enum SyncPushStatus");
      expect(definition).toContain("enum SyncPushReason");
    }
    prod.accounts.hasResource("AWS::DynamoDB::Table", { DeletionPolicy: "Retain" });
  });
});
