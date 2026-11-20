import { CfnOutput, Duration, Fn, RemovalPolicy, Stack, type StackProps } from "aws-cdk-lib";
import * as route53 from "aws-cdk-lib/aws-route53";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as ses from "aws-cdk-lib/aws-ses";
import * as actions from "aws-cdk-lib/aws-ses-actions";
import * as cr from "aws-cdk-lib/custom-resources";
import type { Construct } from "constructs";
import type { Stage } from "./stack.ts";

export interface MailStackProps extends StackProps {
  stage: Stage;
  /** Domain the sign-in codes are sent from. */
  mailDomain: string;
  /** Route 53 public zone that holds mailDomain. Unset: DNS is elsewhere and DkimRecords lists what to add. */
  hostedZone?: string;
  /** Dev only: receive mail for mailDomain into S3 so agents can read codes sent to test addresses. */
  testInbox?: boolean;
}

/**
 * TKL-850: the SES identity a stage's user pool sends from. Separate from the pool's stack because
 * Cognito refuses an unverified identity, and DKIM verification finishes minutes after it's created.
 */
export class MailStack extends Stack {
  constructor(scope: Construct, id: string, props: MailStackProps) {
    super(scope, id, props);
    const { mailDomain, stage } = props;

    const identity = new ses.EmailIdentity(this, "Domain", { identity: ses.Identity.domain(mailDomain) });
    if (stage === "prod") identity.applyRemovalPolicy(RemovalPolicy.RETAIN);

    const dkim = [
      [identity.dkimDnsTokenName1, identity.dkimDnsTokenValue1],
      [identity.dkimDnsTokenName2, identity.dkimDnsTokenValue2],
      [identity.dkimDnsTokenName3, identity.dkimDnsTokenValue3],
    ];

    if (props.hostedZone) {
      const zone = route53.HostedZone.fromLookup(this, "Zone", { domainName: props.hostedZone });
      dkim.forEach(([name, value], i) => new route53.CnameRecord(this, `Dkim${i + 1}`, { zone, recordName: `${name}.`, domainName: value }));
      if (props.testInbox) {
        new route53.MxRecord(this, "InboxMx", {
          zone,
          recordName: mailDomain,
          values: [{ priority: 10, hostName: `inbound-smtp.${this.region}.amazonaws.com` }],
        });
      }
    } else {
      new CfnOutput(this, "DkimRecords", {
        description: "CNAME records to add at the domain's DNS host",
        value: Fn.join(" ; ", dkim.map(([name, value]) => Fn.join(" ", [name, "CNAME", value]))),
      });
    }

    if (props.testInbox) {
      const bucket = new s3.Bucket(this, "Inbox", {
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
        enforceSSL: true,
        lifecycleRules: [{ expiration: Duration.days(7) }],
        removalPolicy: RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
      });
      const ruleSet = new ses.ReceiptRuleSet(this, "InboxRules", {
        receiptRuleSetName: `ConfessionalChristianity-${stage}-inbox`,
        rules: [{ recipients: [mailDomain], actions: [new actions.S3({ bucket, objectKeyPrefix: "inbox/" })], scanEnabled: true }],
      });
      // An account has one active receipt rule set per region; nothing else in this account receives mail.
      const activate = new cr.AwsCustomResource(this, "ActivateInboxRules", {
        onUpdate: {
          service: "SES",
          action: "setActiveReceiptRuleSet",
          parameters: { RuleSetName: ruleSet.receiptRuleSetName },
          physicalResourceId: cr.PhysicalResourceId.of(`active-${ruleSet.receiptRuleSetName}`),
        },
        onDelete: { service: "SES", action: "setActiveReceiptRuleSet", parameters: {} },
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({ resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE }),
        installLatestAwsSdk: false,
      });
      activate.node.addDependency(ruleSet);
      new CfnOutput(this, "InboxBucket", { value: bucket.bucketName });
      new CfnOutput(this, "InboxAddress", { value: `otp-test@${mailDomain}` });
    }

    new CfnOutput(this, "MailDomain", { value: mailDomain });
  }
}
