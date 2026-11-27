import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";
import { fileURLToPath } from "node:url";
import { addAccountSync } from "./sync.ts";

export type Stage = "dev" | "prod";

export interface AccountsStackProps extends StackProps {
  stage: Stage;
  /** SES domain identity the codes are sent from (verified by MailStack before this stack's first deploy). */
  mailDomain: string;
  /** Studio Cognito user pool ID (Studio-dev / Studio-prod) that authorizes account sync tokens. */
  studioUserPoolId: string;
  /** Studio confessional app client ID accepted by the sync AppSync API (appIdClientRegex). */
  studioClientId: string;
}

/**
 * TKL-850: accounts. A Cognito user pool where people sign in with a code emailed to them
 * (choice-based USER_AUTH, EMAIL_OTP). Cognito requires PASSWORD in the allowed first factors, so
 * "no passwords" is enforced three ways: the client allows only USER_AUTH and refresh (no SRP, no
 * USER_PASSWORD_AUTH); account recovery is off so ForgotPassword can't set one; and the NoPassword
 * trigger replaces any password with a random, never-seen one on confirmation and before every sign-in,
 * so a password passed to SignUp or ChangePassword can't sign anyone in.
 */
export class AccountsStack extends Stack {
  constructor(scope: Construct, id: string, props: AccountsStackProps) {
    super(scope, id, props);
    const { stage, mailDomain, studioUserPoolId, studioClientId } = props;
    const isProd = stage === "prod";

    const userPool = new cognito.UserPool(this, "Users", {
      userPoolName: `ConfessionalChristianity-${stage}`,
      featurePlan: cognito.FeaturePlan.ESSENTIALS,
      signInAliases: { email: true },
      autoVerify: { email: true },
      selfSignUpEnabled: true,
      standardAttributes: { email: { required: true, mutable: true } },
      // TKL-889: the Apple user an account belongs to, set once by appleStart (immutable, and the app client can't write
      // it), plus Apple's email and whether Apple verified it, as metadata. These already exist in dev: Cognito never
      // removes or changes a custom attribute, so they must stay exactly as they are.
      customAttributes: {
        appleSubject: new cognito.StringAttribute({ maxLen: 255, mutable: false }),
        appleEmail: new cognito.StringAttribute({ maxLen: 2048, mutable: false }),
        appleEmailVerified: new cognito.StringAttribute({ maxLen: 5, mutable: false }),
      },
      signInPolicy: { allowedFirstAuthFactors: { password: true, emailOtp: true } },
      accountRecovery: cognito.AccountRecovery.NONE,
      // A changed email takes effect only once its code is verified. TKL-889's ProtectAppleEmail refuses to send that
      // code for an Apple account, so its unroutable sign-in address never changes.
      keepOriginal: { email: true },
      email: cognito.UserPoolEmail.withSES({
        fromEmail: `no-reply@${mailDomain}`,
        fromName: "Confessional Christianity",
        sesVerifiedDomain: mailDomain,
        sesRegion: this.region,
      }),
      userVerification: {
        emailSubject: "Your Confessional Christianity code",
        emailBody: "Your code is {####}",
        emailStyle: cognito.VerificationEmailStyle.CODE,
      },
      deletionProtection: isProd,
      removalPolicy: isProd ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
    });

    const noPassword = new lambda.Function(this, "NoPassword", {
      description: "Replaces any Cognito password with a random unknown one (sign-in is by emailed code only)",
      runtime: lambda.Runtime.NODEJS_22_X,
      handler: "index.handler",
      code: lambda.Code.fromAsset(fileURLToPath(new URL("../lambda/no-password", import.meta.url))),
      timeout: Duration.seconds(5),
      memorySize: 256,
      logGroup: new logs.LogGroup(this, "NoPasswordLogs", {
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: RemovalPolicy.DESTROY,
      }),
    });
    userPool.addTrigger(cognito.UserPoolOperation.POST_CONFIRMATION, noPassword);
    userPool.addTrigger(cognito.UserPoolOperation.PRE_AUTHENTICATION, noPassword);
    // A separate policy (not on the function's role) so the pool -> function -> pool reference isn't circular.
    noPassword.role!.attachInlinePolicy(
      new iam.Policy(this, "NoPasswordSetPassword", {
        statements: [new iam.PolicyStatement({ actions: ["cognito-idp:AdminSetUserPassword"], resources: [userPool.userPoolArn] })],
      }),
    );

    // TKL-889: native Sign in with Apple. Cognito can't take Apple's identity token itself, so the app posts it to
    // appleStart (which finds or creates the Apple user and answers its username), then signs in with CUSTOM_AUTH,
    // answering the one challenge with the token and its nonce. Apple and email-code accounts stay separate users.
    const appleCode = lambda.Code.fromAsset(fileURLToPath(new URL("../lambda/apple", import.meta.url)));
    const appleFunction = (id: string, handler: string, description: string, environment?: Record<string, string>) =>
      new lambda.Function(this, id, {
        description,
        runtime: lambda.Runtime.NODEJS_22_X,
        handler,
        code: appleCode,
        environment,
        timeout: Duration.seconds(10),
        memorySize: 256,
        logGroup: new logs.LogGroup(this, `${id}Logs`, { retention: logs.RetentionDays.ONE_MONTH, removalPolicy: RemovalPolicy.DESTROY }),
      });
    userPool.addTrigger(cognito.UserPoolOperation.DEFINE_AUTH_CHALLENGE, appleFunction("AppleDefine", "auth.define", "Apple sign-in: one custom challenge"));
    userPool.addTrigger(cognito.UserPoolOperation.CREATE_AUTH_CHALLENGE, appleFunction("AppleCreate", "auth.create", "Apple sign-in: the challenge"));
    userPool.addTrigger(cognito.UserPoolOperation.VERIFY_AUTH_CHALLENGE_RESPONSE,
      appleFunction("AppleVerify", "auth.verifyChallenge", "Apple sign-in: checks Apple's token, its nonce and the bound Apple user"));
    userPool.addTrigger(cognito.UserPoolOperation.PRE_SIGN_UP,
      appleFunction("ReserveAppleAddress", "auth.reserveAppleAddress", "Self sign-up can't take an Apple account's address"));
    userPool.addTrigger(cognito.UserPoolOperation.CUSTOM_MESSAGE,
      appleFunction("ProtectAppleEmail", "auth.protectAppleEmail", "An Apple account's email can't be changed"));

    const appleStart = appleFunction("AppleStart", "start.handler", "Apple sign-in: finds or creates the Apple user for an identity token",
      { USER_POOL_ID: userPool.userPoolId });
    appleStart.addToRolePolicy(new iam.PolicyStatement({
      actions: ["cognito-idp:AdminGetUser", "cognito-idp:AdminCreateUser", "cognito-idp:AdminSetUserPassword"],
      resources: [userPool.userPoolArn],
    }));
    const appleStartUrl = appleStart.addFunctionUrl({ authType: lambda.FunctionUrlAuthType.NONE });

    const appClient = userPool.addClient("App", {
      userPoolClientName: "ios",
      generateSecret: false,
      // Only the email: SignUp can't set custom:appleSubject (nor the Apple metadata) on itself.
      writeAttributes: new cognito.ClientAttributes().withStandardAttributes({ email: true }),
      preventUserExistenceErrors: true,
      disableOAuth: true,
      // Signing in keeps your progress, so it should never quietly lapse. 10 years is Cognito's maximum.
      refreshTokenValidity: Duration.days(3650),
    });
    (appClient.node.defaultChild as cognito.CfnUserPoolClient).explicitAuthFlows = ["ALLOW_USER_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"];

    const studioPool = cognito.UserPool.fromUserPoolId(this, "StudioUsers", studioUserPoolId);
    // TKL-1071: authorize account sync against the studio pool and confessional client;
    // dev keeps the legacy per-app pool as an additional authorizer until TKL-965 moves Debug over.
    addAccountSync(this, { studioPool, studioClientId, extraPool: isProd ? undefined : userPool }, stage);

    new CfnOutput(this, "Region", { value: this.region });
    new CfnOutput(this, "UserPoolId", { value: userPool.userPoolId });
    new CfnOutput(this, "AppClientId", { value: appClient.userPoolClientId });
    new CfnOutput(this, "AppleStartUrl", { value: appleStartUrl.url });
  }
}
