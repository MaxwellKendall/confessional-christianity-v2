import { describe, expect, it, vi } from "vitest";
import { createHandler } from "../lambda/sync/service.mjs";
import { createDeleteHandler } from "../lambda/sync-delete/service.mjs";
import { createDeleteStore } from "../lambda/sync-delete/store.mjs";

const departing = "11111111-1111-4111-8111-111111111111";
const coGuardian = "22222222-2222-4222-8222-222222222222";
const otherGuardian = "33333333-3333-4333-8333-333333333333";

const ownedChild = "44444444-4444-4444-8444-444444444444";
const sharedOtherChild = "55555555-5555-4555-8555-555555555555";
const privateOtherChild = "55555555-5555-4555-8555-555555555556";
const progress1 = "66666666-6666-4666-8666-666666666661";
const progress2 = "66666666-6666-4666-8666-666666666662";
const progress3 = "66666666-6666-4666-8666-666666666663";
const progress4 = "66666666-6666-4666-8666-666666666664";
const noteId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const cardId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const op = (n) => `77777777-7777-4777-8777-${String(n).padStart(12, "0")}`;

const defaultNow = Date.parse("2026-11-27T10:00:00.000Z");
const stamp = "2026-11-27T10:00:00.000Z";
const later = "2026-11-27T10:01:00.000Z";

function createWorld() {
  const rows = new Map();
  const key = (pk, sk) => JSON.stringify([pk, sk]);

  const db = {
    rows,
    async get(pk, sk) {
      const item = rows.get(key(pk, sk));
      return item ? structuredClone(item) : undefined;
    },
    async query(pk, after, end, limit) {
      return [...rows.values()]
        .filter((row) => row.pk === pk && row.sk > after && row.sk <= end)
        .sort((a, b) => (a.sk < b.sk ? -1 : 1))
        .slice(0, limit)
        .map((r) => structuredClone(r));
    },
    async queryPrefix(pk, prefix) {
      return [...rows.values()]
        .filter((row) => row.pk === pk && row.sk.startsWith(prefix))
        .sort((a, b) => (a.sk < b.sk ? -1 : 1))
        .map((r) => structuredClone(r));
    },
    async putConditional(pk, sk, expected, value) {
      const current = rows.get(key(pk, sk));
      if (expected === undefined ? current !== undefined : current?.version !== expected) {
        return false;
      }
      rows.set(key(pk, sk), structuredClone({ pk, sk, ...value }));
      return true;
    },
    async remove(pk, sk) {
      rows.delete(key(pk, sk));
    },
    async commit(items) {
      for (const { pk, sk, expected, del } of items) {
        if (del) continue;
        if (rows.get(key(pk, sk))?.version !== expected) return false;
      }
      for (const { pk, sk, value, del } of items) {
        if (del) {
          rows.delete(key(pk, sk));
        } else if (value) {
          rows.set(key(pk, sk), structuredClone({ pk, sk, ...value }));
        }
      }
      return true;
    },
  };

  const syncHandler = createHandler(db, { now: () => defaultNow, sleep: async () => {} });
  const deleteHandler = createDeleteHandler(db, { sleep: async () => {} });

  return {
    db,
    rows,
    itemsFor(pk) {
      return [...rows.values()]
        .filter((r) => r.pk === pk)
        .sort((a, b) => (a.sk < b.sk ? -1 : 1));
    },
    grant(childId, memberId, guardianSub) {
      const accessKey = key(`child#${childId}`, "access");
      const current = rows.get(accessKey);
      rows.set(accessKey, {
        ...structuredClone(current),
        version: `grant-${memberId}`,
        guardians: { ...(current?.guardians ?? {}), [memberId]: guardianSub },
      });
      rows.set(key(`account#${guardianSub}`, `member#${childId}`), {
        pk: `account#${guardianSub}`,
        sk: `member#${childId}`,
        version: `grant-${memberId}`,
      });
    },
    push(sub, ...changes) {
      return syncHandler({ identity: { sub }, info: { fieldName: "pushSync" }, arguments: { changes } });
    },
    pull(sub, table, after = "0", limit = 50) {
      return syncHandler({ identity: { sub }, info: { fieldName: "pullSync" }, arguments: { table, after, limit } });
    },
    deleteAccount(payload) {
      return deleteHandler(payload);
    },
  };
}

async function seedFullScenario(world) {
  // 1. Departing user creates an owned child, shares it with coGuardian, adds progress + Lord's Day note & card.
  await world.push(departing, {
    id: op(1), table: "children", row_id: ownedChild, child_id: ownedChild,
    updated_at: stamp, payload: JSON.stringify({ name: "Departing Child", age: 7 }),
  });
  world.grant(ownedChild, "m-co-1", coGuardian);
  await world.push(
    departing,
    {
      id: op(2), table: "catechism_assignments", row_id: progress1, child_id: ownedChild,
      updated_at: stamp, payload: JSON.stringify({ catechism_slug: "catechizing-shorter-catechism", started_at: stamp, started_at_question: 1 }),
    },
    {
      id: op(3), table: "catechism_pacing", row_id: progress2, child_id: ownedChild,
      updated_at: stamp, payload: JSON.stringify({ catechism_slug: "catechizing-shorter-catechism", current_question: 5 }),
    },
    {
      id: op(4), table: "catechism_milestones", row_id: progress3, child_id: ownedChild,
      updated_at: stamp, payload: JSON.stringify({ catechism_slug: "catechizing-shorter-catechism", question: 1, state: "learned", review_count: 3 }),
    },
    {
      id: op(5), table: "lords_day_notes", row_id: noteId, note_id: noteId,
      updated_at: stamp, payload: JSON.stringify({ service_date: "2026-11-22", sermon_title: "The Golden Chain", created_at: stamp }),
    },
    {
      id: op(6), table: "note_cards", row_id: cardId, note_id: noteId,
      updated_at: stamp, payload: JSON.stringify({ kind: "key_point", body: "God works all things for good.", position: 0, edited_by_user: false, created_at: stamp }),
    },
  );

  // 2. Co-guardian owns a shared child (with departing + otherGuardian) and a private child.
  await world.push(coGuardian, {
    id: op(7), table: "children", row_id: sharedOtherChild, child_id: sharedOtherChild,
    updated_at: stamp, payload: JSON.stringify({ name: "CoGuardian Shared Child", age: 9 }),
  });
  world.grant(sharedOtherChild, "m-dep-1", departing);
  world.grant(sharedOtherChild, "m-oth-1", otherGuardian);
  await world.push(coGuardian, {
    id: op(8), table: "catechism_pacing", row_id: progress4, child_id: sharedOtherChild,
    updated_at: stamp, payload: JSON.stringify({ catechism_slug: "catechizing-shorter-catechism", current_question: 12 }),
  });
  await world.push(coGuardian, {
    id: op(9), table: "children", row_id: privateOtherChild, child_id: privateOtherChild,
    updated_at: stamp, payload: JSON.stringify({ name: "CoGuardian Private Child", age: 4 }),
  });
}

describe("sync account deletion hook (infra/SYNC.md)", () => {
  it("runs all 5 contract steps: disables first, deletes owned children/notes/rows, removes memberships, purges stream, and preserves co-guardian data", async () => {
    const world = createWorld();
    await seedFullScenario(world);

    const coGuardianSeqBefore = (await world.db.get(`account#${coGuardian}`, "sequence"))?.sequence;
    expect(coGuardianSeqBefore).toBeDefined();

    // Spy on order: disabled marker must be written before any removal or retirement.
    const order = [];
    const origPut = world.db.putConditional.bind(world.db);
    const origRemove = world.db.remove.bind(world.db);
    const origCommit = world.db.commit.bind(world.db);
    world.db.putConditional = async (pk, sk, expected, value) => {
      order.push(`put:${pk}:${sk}`);
      return origPut(pk, sk, expected, value);
    };
    world.db.remove = async (pk, sk) => {
      order.push(`remove:${pk}:${sk}`);
      return origRemove(pk, sk);
    };
    world.db.commit = async (items) => {
      order.push(`commit:${items.map((i) => `${i.pk}:${i.sk}`).join(",")}`);
      return origCommit(items);
    };

    const result = await world.deleteAccount({ sub: departing, product: "confessional" });
    expect(result).toEqual({ ok: true, sub: departing });

    // Step 1: disabled marker was the very first write.
    expect(order[0]).toBe(`put:account#${departing}:disabled`);

    // Account partition has ONLY the disabled marker (with version).
    const departingAccountItems = world.itemsFor(`account#${departing}`);
    expect(departingAccountItems.map((i) => i.sk)).toEqual(["disabled"]);
    expect(typeof departingAccountItems[0].version).toBe("string");

    // Disabled marker blocks subsequent push and pull even with an unexpired token.
    await expect(world.pull(departing, "children")).rejects.toThrow("Not authorized");
    await expect(world.push(departing, {
      id: op(99), table: "children", row_id: "99999999-9999-4999-8999-999999999999",
      child_id: "99999999-9999-4999-8999-999999999999", updated_at: later,
      payload: JSON.stringify({ name: "Zombie" }),
    })).rejects.toThrow("Not authorized");

    // Step 2: owned child access is retired with ONLY version and retired: true; all rows and catalog entries gone.
    const ownedChildAccess = await world.db.get(`child#${ownedChild}`, "access");
    expect(ownedChildAccess).toEqual({ pk: `child#${ownedChild}`, sk: "access", version: expect.any(String), retired: true });
    expect(world.itemsFor(`child#${ownedChild}`)).toEqual([ownedChildAccess]);
    expect(await world.db.get(`record#children#${ownedChild}`, "value")).toBeUndefined();
    expect(await world.db.get(`record#catechism_assignments#${progress1}`, "value")).toBeUndefined();
    expect(await world.db.get(`record#catechism_pacing#${progress2}`, "value")).toBeUndefined();
    expect(await world.db.get(`record#catechism_milestones#${progress3}`, "value")).toBeUndefined();
    // Co-guardian's reverse membership entry for departing user's child is gone.
    expect(await world.db.get(`account#${coGuardian}`, `member#${ownedChild}`)).toBeUndefined();

    // Step 3: owned Lord's Day note access is retired with ONLY version and retired: true; note & card rows gone.
    const ownedNoteAccess = await world.db.get(`note#${noteId}`, "access");
    expect(ownedNoteAccess).toEqual({ pk: `note#${noteId}`, sk: "access", version: expect.any(String), retired: true });
    expect(world.itemsFor(`note#${noteId}`)).toEqual([ownedNoteAccess]);
    expect(await world.db.get(`record#lords_day_notes#${noteId}`, "value")).toBeUndefined();
    expect(await world.db.get(`record#note_cards#${cardId}`, "value")).toBeUndefined();

    // Step 4: membership in co-guardian's child removed, preserving owner, other co-guardian, progress, and sequence.
    const sharedAccess = await world.db.get(`child#${sharedOtherChild}`, "access");
    expect(sharedAccess).toMatchObject({
      owner: coGuardian,
      guardians: { "m-oth-1": otherGuardian },
    });
    expect(sharedAccess.retired).toBeUndefined();
    expect(await world.db.get(`account#${departing}`, `member#${sharedOtherChild}`)).toBeUndefined();

    // Co-guardian's own children and progress survive completely and remain writable.
    const coChildren = await world.pull(coGuardian, "children");
    expect(coChildren.map((r) => r.id).sort()).toEqual([sharedOtherChild, privateOtherChild].sort());
    const coPacing = await world.pull(coGuardian, "catechism_pacing");
    expect(coPacing.map((r) => r.id)).toEqual([progress4]);
    expect((await world.db.get(`account#${coGuardian}`, "sequence"))?.sequence).toBe(coGuardianSeqBefore);

    // Other guardian still accesses the shared child, and coGuardian can still write to both of their children.
    await expect(world.push(otherGuardian, {
      id: op(10), table: "catechism_pacing", row_id: progress4, child_id: sharedOtherChild,
      updated_at: later, payload: JSON.stringify({ catechism_slug: "catechizing-shorter-catechism", current_question: 13 }),
    })).resolves.toEqual([{ id: op(10), status: "ACCEPTED", reason: null }]);
    await expect(world.push(coGuardian, {
      id: op(11), table: "children", row_id: privateOtherChild, child_id: privateOtherChild,
      updated_at: later, payload: JSON.stringify({ name: "Still Alive", age: 5 }),
    })).resolves.toEqual([{ id: op(11), status: "ACCEPTED", reason: null }]);
  });

  it("resumes cleanly after partial failures at every stage (mid-child, post-finalize, mid-note, mid-membership, mid-stream)", async () => {
    const failurePoints = [
      // Fail during child row deletion (after retiring child access, keeping owner/guardians)
      (call) => call === `remove:record#catechism_pacing#${progress2}:value`,
      // Fail during co-guardian reverse member removal
      (call) => call === `remove:account#${coGuardian}:member#${ownedChild}`,
      // Fail right after finalizing child access, before removing owned# index
      (call) => call === `remove:account#${departing}:owned#${ownedChild}`,
      // Fail during Lord's Day note card deletion
      (call) => call === `remove:record#note_cards#${cardId}:value`,
      // Fail during membership removal from another owner's child
      (call) => call.startsWith(`commit:child#${sharedOtherChild}:access`),
      // Fail during stream change# purge
      (call) => call.startsWith(`remove:account#${departing}:change#`),
      // Fail right before removing sequence
      (call) => call === `remove:account#${departing}:sequence`,
    ];

    for (const shouldFail of failurePoints) {
      const world = createWorld();
      await seedFullScenario(world);

      let injected = false;
      const origRemove = world.db.remove.bind(world.db);
      const origCommit = world.db.commit.bind(world.db);
      world.db.remove = async (pk, sk) => {
        const tag = `remove:${pk}:${sk}`;
        if (!injected && shouldFail(tag)) {
          injected = true;
          throw new Error(`injected failure at ${tag}`);
        }
        return origRemove(pk, sk);
      };
      world.db.commit = async (items) => {
        const tag = `commit:${items.map((i) => `${i.pk}:${i.sk}`).join(",")}`;
        if (!injected && shouldFail(tag)) {
          injected = true;
          throw new Error(`injected failure at ${tag}`);
        }
        return origCommit(items);
      };

      await expect(world.deleteAccount({ sub: departing, product: "confessional" })).rejects.toThrow("injected failure");
      expect(injected).toBe(true);

      // Disabled marker is already in place even after partial failure.
      expect(await world.db.get(`account#${departing}`, "disabled")).toBeDefined();

      // Retry succeeds and leaves exact clean end state.
      await expect(world.deleteAccount({ sub: departing, product: "confessional" })).resolves.toEqual({ ok: true, sub: departing });
      expect(world.itemsFor(`account#${departing}`).map((i) => i.sk)).toEqual(["disabled"]);
      expect(await world.db.get(`child#${ownedChild}`, "access")).toEqual({
        pk: `child#${ownedChild}`, sk: "access", version: expect.any(String), retired: true,
      });
      expect(await world.db.get(`note#${noteId}`, "access")).toEqual({
        pk: `note#${noteId}`, sk: "access", version: expect.any(String), retired: true,
      });
      expect(await world.db.get(`account#${coGuardian}`, `member#${ownedChild}`)).toBeUndefined();
      expect((await world.db.get(`child#${sharedOtherChild}`, "access")).guardians).toEqual({ "m-oth-1": otherGuardian });

      // Idempotent second full run.
      await expect(world.deleteAccount({ sub: departing, product: "confessional" })).resolves.toEqual({ ok: true, sub: departing });
      expect(world.itemsFor(`account#${departing}`).map((i) => i.sk)).toEqual(["disabled"]);
    }
  });

  it("refuses invalid sub or wrong product, and never deletes a child owned by someone else", async () => {
    const world = createWorld();
    await seedFullScenario(world);

    await expect(world.deleteAccount({})).rejects.toThrow("Invalid subject");
    await expect(world.deleteAccount({ sub: "not-a-uuid", product: "confessional" })).rejects.toThrow("Invalid subject");
    await expect(world.deleteAccount({ sub: departing, product: "remix" })).rejects.toThrow("Unexpected product");

    // Simulate a stray owned# entry pointing to another user's child: must not touch that child.
    world.rows.set(JSON.stringify([`account#${departing}`, `owned#${privateOtherChild}`]), {
      pk: `account#${departing}`, sk: `owned#${privateOtherChild}`, version: "stray",
    });
    await expect(world.deleteAccount({ sub: departing, product: "confessional" })).rejects.toThrow("Ownership mismatch");
    const otherAccess = await world.db.get(`child#${privateOtherChild}`, "access");
    expect(otherAccess.owner).toBe(coGuardian);
    expect(otherAccess.retired).toBeUndefined();
    expect(await world.db.get(`record#children#${privateOtherChild}`, "value")).toBeDefined();
  });
});

describe("sync delete DynamoDB store adapter", () => {
  class GetCommand { constructor(input) { this.input = input; } }
  class QueryCommand extends GetCommand {}
  class PutCommand extends GetCommand {}
  class DeleteCommand extends GetCommand {}
  class TransactWriteCommand extends GetCommand {}

  it("paginates consistent prefix queries, runs conditional puts/commits, and deletes items", async () => {
    const send = vi.fn()
      .mockResolvedValueOnce({ Items: [{ pk: "account#u", sk: "change#1" }], LastEvaluatedKey: { pk: "account#u", sk: "change#1" } })
      .mockResolvedValueOnce({ Items: [{ pk: "account#u", sk: "change#2" }] })
      .mockResolvedValueOnce({})
      .mockRejectedValueOnce(Object.assign(new Error("exists"), { name: "ConditionalCheckFailedException" }))
      .mockResolvedValueOnce({})
      .mockResolvedValueOnce({});

    const store = createDeleteStore({ send }, "sync-table", {
      GetCommand, QueryCommand, PutCommand, DeleteCommand, TransactWriteCommand,
    });

    const queried = await store.queryPrefix("account#u", "change#");
    expect(queried).toEqual([{ pk: "account#u", sk: "change#1" }, { pk: "account#u", sk: "change#2" }]);
    expect(send.mock.calls[0][0].input).toMatchObject({
      TableName: "sync-table",
      KeyConditionExpression: "#pk = :pk AND begins_with(#sk, :prefix)",
      ConsistentRead: true,
    });
    expect(send.mock.calls[1][0].input.ExclusiveStartKey).toEqual({ pk: "account#u", sk: "change#1" });

    await expect(store.putConditional("account#u", "disabled", undefined, { version: "v1" })).resolves.toBe(true);
    await expect(store.putConditional("account#u", "disabled", undefined, { version: "v2" })).resolves.toBe(false);

    await expect(store.commit([
      { pk: "child#c", sk: "access", expected: "v1", value: { version: "v2", owner: "o", guardians: {} } },
      { pk: "account#u", sk: "member#c", del: true },
    ])).resolves.toBe(true);
    expect(send.mock.calls[4][0].input.TransactItems).toMatchObject([
      { Put: { TableName: "sync-table", ConditionExpression: "#version = :version" } },
      { Delete: { TableName: "sync-table", Key: { pk: "account#u", sk: "member#c" } } },
    ]);

    await store.remove("account#u", "sequence");
    expect(send.mock.calls[5][0].input).toMatchObject({
      TableName: "sync-table", Key: { pk: "account#u", sk: "sequence" },
    });
  });
});
