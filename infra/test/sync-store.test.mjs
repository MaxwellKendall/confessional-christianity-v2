import { expect, it, vi } from "vitest";
import { createStore } from "../lambda/sync/store.mjs";

class GetCommand {
  constructor(input) { this.input = input; }
}

class QueryCommand extends GetCommand {}
class TransactWriteCommand extends GetCommand {}

function fixture() {
  const send = vi.fn().mockResolvedValue({});
  const store = createStore({ send }, "sync", { GetCommand, QueryCommand, TransactWriteCommand });
  return { store, send };
}

it("checks versions and publishes all rows in one DynamoDB transaction", async () => {
  const { store, send } = fixture();
  const record = { pk: "record", sk: "value", version: "new" };
  const change = { pk: "account", sk: "change#1", version: "new" };
  await expect(store.commit([
    { pk: "child", sk: "access", expected: "membership" },
    { pk: "record", sk: "value", expected: "old", value: record },
    { pk: "account", sk: "change#1", value: change },
  ])).resolves.toBe(true);
  expect(send).toHaveBeenCalledExactlyOnceWith(expect.any(TransactWriteCommand));
  expect(send.mock.calls[0][0].input.TransactItems).toMatchObject([
    { ConditionCheck: { Key: { pk: "child", sk: "access" }, ExpressionAttributeValues: { ":version": "membership" } } },
    { Put: { Item: record, ExpressionAttributeValues: { ":version": "old" } } },
    { Put: { Item: change, ConditionExpression: "attribute_not_exists(#pk)" } },
  ]);
});

it("reads from the base table consistently and bounds the cursor range", async () => {
  const { store, send } = fixture();
  await store.get("account", "sequence");
  await store.query("account", "change#children#01", "change#children#09", 3);
  expect(send.mock.calls[0][0].input).toMatchObject({ ConsistentRead: true });
  expect(send.mock.calls[1][0].input).toMatchObject({
    ConsistentRead: true,
    ScanIndexForward: true,
    Limit: 3,
    ExpressionAttributeValues: {
      ":pk": "account",
      ":start": "change#children#01#",
      ":end": "change#children#09",
    },
  });
});

it("distinguishes optimistic write conflicts from other transaction errors", async () => {
  const { store, send } = fixture();
  const error = (Code) => Object.assign(new Error(Code), {
    name: "TransactionCanceledException", CancellationReasons: [{ Code }],
  });
  send.mockRejectedValueOnce(error("ConditionalCheckFailed")).mockRejectedValueOnce(error("ValidationError"));
  await expect(store.commit([])).resolves.toBe(false);
  await expect(store.commit([])).rejects.toThrow("ValidationError");
});
