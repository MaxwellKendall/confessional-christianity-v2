import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  TransactWriteCommand,
} from "@aws-sdk/lib-dynamodb";
import { createDeleteHandler } from "./service.mjs";
import { createDeleteStore } from "./store.mjs";

const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));
export const handler = createDeleteHandler(
  createDeleteStore(client, process.env.SYNC_TABLE, {
    GetCommand,
    QueryCommand,
    PutCommand,
    DeleteCommand,
    TransactWriteCommand,
  }),
);
