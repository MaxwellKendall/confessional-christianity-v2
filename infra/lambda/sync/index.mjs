import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand } from "@aws-sdk/lib-dynamodb";
import { createHandler } from "./service.mjs";
import { createStore } from "./store.mjs";

const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));
export const handler = createHandler(createStore(client, process.env.SYNC_TABLE, {
  GetCommand, QueryCommand, TransactWriteCommand,
}));
