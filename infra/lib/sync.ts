import { CfnOutput, Duration, RemovalPolicy } from "aws-cdk-lib";
import * as appsync from "aws-cdk-lib/aws-appsync";
import type { IUserPool } from "aws-cdk-lib/aws-cognito";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";
import { fileURLToPath } from "node:url";

export interface AccountSyncAuth {
  /** Studio Cognito user pool (Studio-dev / Studio-prod). */
  studioPool: IUserPool;
  /** Studio confessional app client ID; restricts accepted tokens to this product's client. */
  studioClientId: string;
  /** Optional legacy per-app pool kept on dev until Debug moves to Studio-dev (TKL-965). */
  extraPool?: IUserPool;
}

export function addAccountSync(scope: Construct, auth: AccountSyncAuth, stage: string) {
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

  // TKL-1071: cleanup hook invoked by studio-platform's DeleteAccount Lambda with { sub, product }.
  const deleteHandler = new lambda.Function(scope, "AccountSyncDelete", {
    functionName: `ConfessionalChristianity-sync-delete-${stage}`,
    description: "Deletes a departing account's synced children, progress, Lord's Day notes and stream references",
    runtime: lambda.Runtime.NODEJS_22_X,
    handler: "index.handler",
    code: lambda.Code.fromAsset(fileURLToPath(new URL("../lambda/sync-delete", import.meta.url))),
    environment: { SYNC_TABLE: table.tableName },
    timeout: Duration.seconds(25),
    memorySize: 256,
    logGroup: new logs.LogGroup(scope, "AccountSyncDeleteLogs", {
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    }),
  });
  deleteHandler.addToRolePolicy(new iam.PolicyStatement({
    actions: [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:ConditionCheckItem",
    ],
    resources: [table.tableArn],
  }));

  const api = new appsync.GraphqlApi(scope, "AccountSyncApi", {
    name: `ConfessionalChristianity-sync-${stage}`,
    definition: appsync.Definition.fromFile(fileURLToPath(new URL("../schema/sync.graphql", import.meta.url))),
    authorizationConfig: {
      defaultAuthorization: {
        authorizationType: appsync.AuthorizationType.USER_POOL,
        userPoolConfig: {
          userPool: auth.studioPool,
          appIdClientRegex: `^${auth.studioClientId}$`,
        },
      },
      additionalAuthorizationModes: auth.extraPool
        ? [{ authorizationType: appsync.AuthorizationType.USER_POOL, userPoolConfig: { userPool: auth.extraPool } }]
        : undefined,
    },
    introspectionConfig: appsync.IntrospectionConfig.DISABLED,
  });
  const source = api.addLambdaDataSource("AccountSync", handler);
  source.createResolver("PushSync", { typeName: "Mutation", fieldName: "pushSync" });
  source.createResolver("PullSync", { typeName: "Query", fieldName: "pullSync" });
  new CfnOutput(scope, "AccountSyncUrl", { value: api.graphqlUrl });
  new CfnOutput(scope, "AccountSyncTableName", { value: table.tableName });
  new CfnOutput(scope, "AccountSyncDeleteFunctionName", { value: deleteHandler.functionName });
}
