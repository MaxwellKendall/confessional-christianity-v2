export function createDeleteStore(
  client,
  table,
  { GetCommand, QueryCommand, PutCommand, DeleteCommand, TransactWriteCommand },
) {
  return {
    async get(pk, sk) {
      const result = await client.send(new GetCommand({
        TableName: table,
        Key: { pk, sk },
        ConsistentRead: true,
      }));
      return result.Item;
    },

    async queryPrefix(pk, prefix) {
      const items = [];
      let ExclusiveStartKey;
      do {
        const result = await client.send(new QueryCommand({
          TableName: table,
          KeyConditionExpression: "#pk = :pk AND begins_with(#sk, :prefix)",
          ExpressionAttributeNames: { "#pk": "pk", "#sk": "sk" },
          ExpressionAttributeValues: { ":pk": pk, ":prefix": prefix },
          ConsistentRead: true,
          ExclusiveStartKey,
        }));
        if (result.Items?.length) items.push(...result.Items);
        ExclusiveStartKey = result.LastEvaluatedKey;
      } while (ExclusiveStartKey);
      return items;
    },

    async putConditional(pk, sk, expected, value) {
      const condition = expected === undefined
        ? { ConditionExpression: "attribute_not_exists(#pk)", ExpressionAttributeNames: { "#pk": "pk" } }
        : {
            ConditionExpression: "#version = :version",
            ExpressionAttributeNames: { "#version": "version" },
            ExpressionAttributeValues: { ":version": expected },
          };
      try {
        await client.send(new PutCommand({
          TableName: table,
          Item: { pk, sk, ...value },
          ...condition,
        }));
        return true;
      } catch (error) {
        if (error.name === "ConditionalCheckFailedException") return false;
        throw error;
      }
    },

    async remove(pk, sk) {
      await client.send(new DeleteCommand({
        TableName: table,
        Key: { pk, sk },
      }));
    },

    async commit(writes) {
      const TransactItems = writes.map(({ pk, sk, expected, value, del }) => {
        if (del) {
          return { Delete: { TableName: table, Key: { pk, sk } } };
        }
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
        const codes = error.CancellationReasons?.map((reason) => reason.Code);
        if (
          error.name === "TransactionCanceledException" &&
          codes?.length &&
          codes.every((code) => ["None", "ConditionalCheckFailed", "TransactionConflict"].includes(code))
        ) {
          return false;
        }
        throw error;
      }
    },
  };
}
