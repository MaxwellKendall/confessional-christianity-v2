import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from "aws-cdk-lib";
import * as cognito from "aws-cdk-lib/aws-cognito";
import type { Construct } from "constructs";

export type Stage = "dev" | "prod";

export interface AccountsStackProps extends StackProps {
  stage: Stage;
  /** SES domain identity the codes are sent from (verified by MailStack before this stack's first deploy). */
  mailDomain: string;
}

/**
 * TKL-850: accounts. A Cognito user pool where people sign in with a 6-digit code emailed to them
 * (choice-based USER_AUTH, EMAIL_OTP). Cognito requires PASSWORD in the allowed first factors, so
 * "no passwords" is enforced on the client: it allows only USER_AUTH and refresh (no SRP, no
 * USER_PASSWORD_AUTH), and account recovery is off so ForgotPassword can't set one.
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

    const appClient = userPool.addClient("App", {
      userPoolClientName: "ios",
      generateSecret: false,
      preventUserExistenceErrors: true,
      disableOAuth: true,
      // Signing in keeps your progress, so it should never quietly lapse. 10 years is Cognito's maximum.
      refreshTokenValidity: Duration.days(3650),
    });
    (appClient.node.defaultChild as cognito.CfnUserPoolClient).explicitAuthFlows = ["ALLOW_USER_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"];

    new CfnOutput(this, "Region", { value: this.region });
    new CfnOutput(this, "UserPoolId", { value: userPool.userPoolId });
    new CfnOutput(this, "AppClientId", { value: appClient.userPoolClientId });
  }
}
