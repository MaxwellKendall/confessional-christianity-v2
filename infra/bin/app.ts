import { App } from "aws-cdk-lib";
import { AccountsStack, type Stage } from "../lib/stack.ts";
import { MailStack } from "../lib/mail.ts";

const app = new App();
const stage = app.node.getContext("stage") as Stage;
const stages = app.node.getContext("stages") as Record<
  Stage,
  { mailDomain: string; hostedZone?: string; testInbox?: boolean; studioUserPoolId: string; studioClientId: string }
>;
const config = stages[stage];
if (!config) throw new Error(`Unknown stage "${stage}": use -c stage=dev or -c stage=prod`);

// Account 397614038040 (profile aicoach-dev), shared with ai-coach and remix as separate stacks.
const env = { account: process.env.CDK_DEFAULT_ACCOUNT, region: app.node.getContext("region") as string };

const mail = new MailStack(app, `ConfessionalChristianityMail-${stage}`, { env, stage, ...config });
const accounts = new AccountsStack(app, `ConfessionalChristianity-${stage}`, {
  env,
  stage,
  mailDomain: config.mailDomain,
  studioUserPoolId: config.studioUserPoolId,
  studioClientId: config.studioClientId,
});
accounts.addStackDependency(mail);
