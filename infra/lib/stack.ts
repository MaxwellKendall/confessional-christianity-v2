import { ArnFormat, CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import { NodejsFunction } from "aws-cdk-lib/aws-lambda-nodejs";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";
import { fileURLToPath } from "node:url";

export type Stage = "dev" | "prod";

export interface AccountsStackProps extends StackProps {
  stage: Stage;
  /** SES domain identity the codes are sent from (verified by MailStack before this stack's first deploy). */
  mailDomain: string;
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
    const { stage, mailDomain } = props;
    const isProd = stage === "prod";

    const userPool = new cognito.UserPool(this, "Users", {
      userPoolName: `ConfessionalChristianity-${stage}`,
      featurePlan: cognito.FeaturePlan.ESSENTIALS,
      signInAliases: { email: true },
      autoVerify: { email: true },
      selfSignUpEnabled: true,
      standardAttributes: { email: { required: true, mutable: true } },
      signInPolicy: { allowedFirstAuthFactors: { password: true, emailOtp: true } },
      accountRecovery: cognito.AccountRecovery.NONE,
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

    const appClient = userPool.addClient("App", {
      userPoolClientName: "ios",
      generateSecret: false,
      preventUserExistenceErrors: true,
      disableOAuth: true,
      // Signing in keeps your progress, so it should never quietly lapse. 10 years is Cognito's maximum.
      refreshTokenValidity: Duration.days(3650),
    });
    (appClient.node.defaultChild as cognito.CfnUserPoolClient).explicitAuthFlows = ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"];

    const appleSecretId = `confessional/${stage}/apple-signin`;
    const deleteAccount = new NodejsFunction(this, "DeleteAccount", {
      entry: fileURLToPath(new URL("../lambda/deleteAccount.ts", import.meta.url)),
      runtime: lambda.Runtime.NODEJS_22_X,
      timeout: Duration.seconds(25),
      environment: {
        USER_POOL_ID: userPool.userPoolId,
        APP_CLIENT_ID: appClient.userPoolClientId,
        APPLE_SECRET_ID: appleSecretId,
      },
      logGroup: new logs.LogGroup(this, "DeleteAccountLogs", {
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: RemovalPolicy.DESTROY,
      }),
    });
    deleteAccount.addToRolePolicy(new iam.PolicyStatement({
      actions: ["cognito-idp:AdminDeleteUser"],
      resources: [userPool.userPoolArn],
    }));
    deleteAccount.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue"],
      resources: [this.formatArn({ service: "secretsmanager", resource: "secret", resourceName: `${appleSecretId}-??????`, arnFormat: ArnFormat.COLON_RESOURCE_NAME })],
    }));
    const deleteAccountUrl = deleteAccount.addFunctionUrl({ authType: lambda.FunctionUrlAuthType.NONE });
    new CfnOutput(this, "DeleteAccountUrl", { value: deleteAccountUrl.url });

    new CfnOutput(this, "Region", { value: this.region });
    new CfnOutput(this, "UserPoolId", { value: userPool.userPoolId });
    new CfnOutput(this, "AppClientId", { value: appClient.userPoolClientId });
  }
}
