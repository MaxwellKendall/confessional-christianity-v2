export function createStore(client, table, { GetCommand, QueryCommand, TransactWriteCommand }) {
  return {
    async get(pk, sk) {
      const result = await client.send(new GetCommand({
        TableName: table, Key: { pk, sk }, ConsistentRead: true,
      }));
      return result.Item;
    },

    async query(pk, after, end, limit) {
      const result = await client.send(new QueryCommand({
        TableName: table,
        KeyConditionExpression: "#pk = :pk AND #sk BETWEEN :start AND :end",
        ExpressionAttributeNames: { "#pk": "pk", "#sk": "sk" },
        // The stored suffix is digits only, so # sorts immediately after the cursor
        // for this keyspace and excludes the cursor row itself.
        ExpressionAttributeValues: { ":pk": pk, ":start": `${after}#`, ":end": end },
        ConsistentRead: true,
        ScanIndexForward: true,
        Limit: limit,
      }));
      return result.Items ?? [];
    },

    async commit(writes) {
      const TransactItems = writes.map(({ pk, sk, expected, value }) => {
        const check = expected === undefined
          ? { ConditionExpression: "attribute_not_exists(#pk)", ExpressionAttributeNames: { "#pk": "pk" } }
          : {
              ConditionExpression: "#version = :version",
              ExpressionAttributeNames: { "#version": "version" },
              ExpressionAttributeValues: { ":version": expected },
            };
        const options = { TableName: table, ...check };
        return value
          ? { Put: { ...options, Item: { pk, sk, ...value } } }
          : { ConditionCheck: { ...options, Key: { pk, sk } } };
      });
      try {
        await client.send(new TransactWriteCommand({ TransactItems }));
        return true;
      } catch (error) {
        const codes = error.CancellationReasons?.map(reason => reason.Code);
        if (error.name === "TransactionCanceledException" && codes?.length &&
            codes.every(code => ["None", "ConditionalCheckFailed", "TransactionConflict"].includes(code))) return false;
        throw error;
      }
    },
  };
}
