import { CfnOutput, Duration, RemovalPolicy } from "aws-cdk-lib";
import * as appsync from "aws-cdk-lib/aws-appsync";
import type { IUserPool } from "aws-cdk-lib/aws-cognito";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";
import { fileURLToPath } from "node:url";

export function addAccountSync(scope: Construct, pool: IUserPool, stage: string) {
  const isProd = stage === "prod";
  const table = new dynamodb.Table(scope, "AccountSyncTable", {
    partitionKey: { name: "pk", type: dynamodb.AttributeType.STRING },
    sortKey: { name: "sk", type: dynamodb.AttributeType.STRING },
    billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
    removalPolicy: isProd ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
    deletionProtection: isProd,
  });

  const handler = new lambda.Function(scope, "AccountSyncHandler", {
    runtime: lambda.Runtime.NODEJS_22_X,
    handler: "index.handler",
    code: lambda.Code.fromAsset(fileURLToPath(new URL("../lambda/sync", import.meta.url))),
    environment: { SYNC_TABLE: table.tableName },
    timeout: Duration.seconds(25),
    logGroup: new logs.LogGroup(scope, "AccountSyncLogs", {
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    }),
  });
  handler.addToRolePolicy(new iam.PolicyStatement({
    actions: ["dynamodb:GetItem", "dynamodb:Query"],
    resources: [table.tableArn],
  }));

  handler.addToRolePolicy(new iam.PolicyStatement({
    actions: ["dynamodb:PutItem", "dynamodb:ConditionCheckItem"],
    resources: [table.tableArn],
    conditions: { StringEquals: { "dynamodb:EnclosingOperation": "TransactWriteItems" } },
  }));

  const api = new appsync.GraphqlApi(scope, "AccountSyncApi", {
    name: `ConfessionalChristianity-sync-${stage}`,
    definition: appsync.Definition.fromFile(fileURLToPath(new URL("../schema/sync.graphql", import.meta.url))),
    authorizationConfig: {
      defaultAuthorization: { authorizationType: appsync.AuthorizationType.USER_POOL, userPoolConfig: { userPool: pool } },
    },
    introspectionConfig: appsync.IntrospectionConfig.DISABLED,
  });
  const source = api.addLambdaDataSource("AccountSync", handler);
  source.createResolver("PushSync", { typeName: "Mutation", fieldName: "pushSync" });
  source.createResolver("PullSync", { typeName: "Query", fieldName: "pullSync" });
  new CfnOutput(scope, "AccountSyncUrl", { value: api.graphqlUrl });
}
