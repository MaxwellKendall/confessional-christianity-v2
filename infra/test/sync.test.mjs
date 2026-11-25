import { expect, it } from "vitest";
import { createHandler } from "../lambda/sync/service.mjs";

const owner = "11111111-1111-4111-8111-111111111111";
const guardian = "22222222-2222-4222-8222-222222222222";
const stranger = "33333333-3333-4333-8333-333333333333";
const child = "44444444-4444-4444-8444-444444444444";
const secondChild = "55555555-5555-4555-8555-555555555555";
const progress = "66666666-6666-4666-8666-666666666666";
const secondProgress = "66666666-6666-4666-8666-666666666667";
const operation = "77777777-7777-4777-8777-777777777777";
const secondOperation = "88888888-8888-4888-8888-888888888888";
const thirdOperation = "99999999-9999-4999-8999-999999999999";

const defaultNow = Date.parse("2026-11-21T10:00:00.000Z");

function fixture({ now = () => defaultNow, sleep = async () => {} } = {}) {
  const rows = new Map();
  const key = (pk, sk) => JSON.stringify([pk, sk]);
  const db = {
    async get(pk, sk) {
      return rows.get(key(pk, sk));
    },
    async query(pk, after, end, limit) {
      return [...rows.values()].filter(row => row.pk === pk && row.sk > after && row.sk <= end)
        .sort((a, b) => a.sk < b.sk ? -1 : 1).slice(0, limit);
    },
    async commit(items) {
      for (const { pk, sk, expected } of items) {
        if (rows.get(key(pk, sk))?.version !== expected) return false;
      }
      for (const { pk, sk, value } of items) {
        if (value) rows.set(key(pk, sk), { pk, sk, ...value });
      }
      return true;
    },
  };
  const handler = createHandler(db, { now, sleep });
  return {
    db,
    grant() {
      const id = key(`child#${child}`, "access");
      const current = rows.get(id);
      rows.set(id, { ...current, version: "grant", guardians: { [operation]: guardian } });
    },
    revoke() {
      const id = key(`child#${child}`, "access");
      const current = rows.get(id);
      rows.set(id, { ...current, version: "revoke", guardians: {} });
    },
    push(sub, ...changes) {
      return handler({ identity: { sub }, info: { fieldName: "pushSync" }, arguments: { changes } });
    },
    pull(sub, table = "children", after = "0", limit = 25) {
      return handler({ identity: { sub }, info: { fieldName: "pullSync" }, arguments: { table, after, limit } });
    },
  };
}

const accepted = (id = operation) => ({ id, status: "ACCEPTED", reason: null });
const rejected = (reason, id = operation) => ({ id, status: "REJECTED", reason });
const retry = (reason = "CONTENTION", id = operation) => ({ id, status: "RETRY", reason });

const stamp = "2026-11-21T10:00:00.000Z";
const later = "2026-11-21T10:01:00.000Z";
const profile = {
  id: operation, table: "children", row_id: child, child_id: child,
  updated_at: stamp, payload: JSON.stringify({ name: "Child" }),
};
const assignment = {
  ...profile, table: "catechism_assignments", row_id: progress,
  payload: JSON.stringify({ catechism_slug: "shorter" }),
};

it("derives ownership and authorizes each shared record using trusted membership", async () => {
  const { push, pull, grant } = fixture();
  await expect(push(undefined, profile)).rejects.toThrow("Not authorized");
  await expect(push(owner, { ...profile, owner_sub: stranger })).resolves.toEqual([rejected("INVALID_INPUT")]);
  await expect(push(owner, { ...profile, payload: '{"name":"Child","guardian_sub":"forged"}' }))
    .resolves.toEqual([rejected("INVALID_INPUT")]);
  await expect(push(owner, { ...profile, table: "guardian_memberships" }))
    .resolves.toEqual([rejected("INVALID_INPUT")]);
  await expect(push(owner, profile)).resolves.toEqual([accepted()]);
  await expect(push(guardian, assignment)).resolves.toEqual([rejected("UNAUTHORIZED")]);
  grant();
  await expect(push(guardian, assignment)).resolves.toEqual([accepted()]);
  await expect(push(guardian, { ...profile, payload: null, updated_at: later, deleted_at: later }))
    .resolves.toEqual([rejected("UNAUTHORIZED")]);
  await expect(push(stranger, { ...profile, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED")]);
  await expect(push(stranger, { ...assignment, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED")]);
  await expect(pull(stranger, "catechism_assignments")).resolves.toEqual([]);
  for (const subject of [guardian, owner]) {
    const [record] = await pull(subject, "catechism_assignments");
    expect(record).toMatchObject({ id: progress, child_id: child, updated_at: stamp });
  }
});

it("acknowledges replay and stale writes, pages strictly after each cursor and includes tombstones", async () => {
  const { push, pull } = fixture();
  await expect(push(owner, profile, { ...profile, id: secondOperation, row_id: secondChild, child_id: secondChild }))
    .resolves.toEqual([accepted(operation), accepted(secondOperation)]);
  await expect(push(owner, profile, { ...profile, id: secondOperation, updated_at: "2025-01-01T00:00:00.000Z" }))
    .resolves.toEqual([accepted(operation), accepted(secondOperation)]);
  const [first] = await pull(owner, "children", "0", 1);
  const [second] = await pull(owner, "children", first.change_id, 1);
  expect([first.change_id, second.change_id]).toEqual(["1", "2"]);
  await expect(pull(owner, "children", second.change_id)).resolves.toEqual([]);
  await expect(push(owner, { ...profile, payload: null, updated_at: later, deleted_at: later }))
    .resolves.toEqual([accepted()]);
  await expect(pull(owner, "children", second.change_id)).resolves.toMatchObject([
    { id: child, deleted_at: later, payload: null, change_id: "3" },
  ]);
});

it("never publishes a reserved cursor while a write is paused, and retries a conflicting transaction", async () => {
  const { db, push, pull, grant } = fixture();
  await push(owner, profile);
  grant();
  const commit = db.commit;
  let resume;
  let entered;
  const paused = new Promise(resolve => { entered = resolve; });
  const hold = new Promise(resolve => { resume = resolve; });
  let first = true;
  db.commit = async (items) => {
    if (first) {
      first = false;
      entered();
      await hold;
    }
    return commit(items);
  };
  const slow = push(guardian, assignment);
  await paused;
  await expect(pull(owner, "catechism_assignments")).resolves.toEqual([]);
  await push(owner, { ...assignment, row_id: secondChild });
  const readers = await Promise.all([owner, guardian].flatMap(sub => [
    pull(sub, "catechism_assignments"), pull(sub, "catechism_assignments"),
  ]));
  expect(readers.map(page => page.map((record) => record.id))).toEqual(Array(4).fill([secondChild]));
  resume();
  await expect(slow).resolves.toEqual([accepted()]);
  for (const [index, subject] of [owner, guardian].entries()) {
    const cursor = readers[index * 2][0].change_id;
    const [next] = await pull(subject, "catechism_assignments", cursor);
    expect(next.id).toBe(progress);
    expect(BigInt(next.change_id)).toBeGreaterThan(BigInt(cursor));
  }
});

it("rechecks current access and rejects writes to a retired child ID", async () => {
  const { db, push, pull, grant } = fixture();
  await push(owner, profile);
  grant();
  await push(guardian, assignment);
  const childKey = `child#${child}`;
  const access = await db.get(childKey, "access");
  await db.commit([{ pk: childKey, sk: "access", expected: access.version, value: { version: "retired", retired: true } }]);
  await expect(pull(guardian, "catechism_assignments")).resolves.toEqual([]);
  await expect(push(guardian, { ...assignment, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED")]);
  await expect(push(owner, { ...profile, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED")]);
});

it("blocks sync from an account that has started deletion", async () => {
  const { db, push, pull } = fixture();
  await push(owner, profile);
  await db.commit([{ pk: `account#${owner}`, sk: "disabled", value: { version: "disabled" } }]);
  await expect(pull(owner)).rejects.toThrow("Not authorized");
  await expect(push(owner, { ...profile, updated_at: later })).rejects.toThrow("Not authorized");
});

it("drops a revoked guardian's stale outbox entry as permanently rejected while accepting later valid entries", async () => {
  const { push, pull, grant, revoke } = fixture();
  await expect(push(owner, profile)).resolves.toEqual([accepted()]);
  grant();

  const guardianChild = {
    id: secondOperation, table: "children", row_id: secondChild, child_id: secondChild,
    updated_at: stamp, payload: JSON.stringify({ name: "Guardian Child" }),
  };
  await expect(push(guardian, guardianChild)).resolves.toEqual([accepted(secondOperation)]);

  // Guardian queues an edit to the shared child and an edit to their own child, then loses access to the shared child.
  const outbox = [
    { ...assignment, id: operation, updated_at: later },
    {
      id: thirdOperation, table: "catechism_assignments", row_id: secondProgress, child_id: secondChild,
      updated_at: later, payload: JSON.stringify({ catechism_slug: "heidelberg" }),
    },
  ];
  revoke();

  const results = await push(guardian, ...outbox);
  expect(results).toEqual([
    rejected("UNAUTHORIZED", operation),
    accepted(thirdOperation),
  ]);

  // A transport drops ACCEPTED and REJECTED entries and only retries RETRY entries.
  const remaining = outbox.filter((_, index) => results[index].status === "RETRY");
  expect(remaining).toEqual([]);
  await expect(pull(owner, "catechism_assignments")).resolves.toEqual([]);
  await expect(pull(guardian, "catechism_assignments")).resolves.toMatchObject([
    { id: secondProgress, child_id: secondChild, updated_at: later },
  ]);
});

it("reports retryable write contention separately from permanent rejection and stops batch execution in order", async () => {
  const { db, push, pull } = fixture();
  const realCommit = db.commit;
  db.commit = async () => false;

  const batch = [
    profile,
    { ...assignment, id: secondOperation },
  ];
  const contended = await push(owner, ...batch);
  expect(contended).toEqual([
    retry("CONTENTION", operation),
    retry("CONTENTION", secondOperation),
  ]);

  // Contention clears: the client retries the unacknowledged entries in order and both succeed.
  db.commit = realCommit;
  const remaining = batch.filter((_, index) => contended[index].status === "RETRY");
  expect(remaining).toHaveLength(2);
  await expect(push(owner, ...remaining)).resolves.toEqual([
    accepted(operation),
    accepted(secondOperation),
  ]);
  await expect(pull(owner, "catechism_assignments")).resolves.toMatchObject([
    { id: progress, child_id: child, updated_at: stamp },
  ]);
});

it("rejects updated_at and deleted_at more than 24 hours past server time without locking out later writes", async () => {
  const { push, pull } = fixture({ now: () => defaultNow });
  const atLimit = "2026-11-22T10:00:00.000Z";
  const overLimit = "2026-11-22T10:00:00.001Z";
  const yearsAhead = "2030-01-01T00:00:00.000Z";

  await expect(push(owner,
    { ...profile, id: operation, updated_at: yearsAhead },
    { ...profile, id: secondOperation, updated_at: overLimit },
    { ...profile, id: thirdOperation, updated_at: stamp },
  )).resolves.toEqual([
    rejected("CLOCK_SKEW", operation),
    rejected("CLOCK_SKEW", secondOperation),
    accepted(thirdOperation),
  ]);

  // A write at the exact 24h boundary is accepted.
  await expect(push(owner, { ...profile, id: operation, updated_at: atLimit }))
    .resolves.toEqual([accepted(operation)]);

  // A tombstone with a future deleted_at past 24h is rejected.
  await expect(push(owner, { ...profile, id: secondOperation, payload: null, updated_at: atLimit, deleted_at: overLimit }))
    .resolves.toEqual([rejected("CLOCK_SKEW", secondOperation)]);

  const [stored] = await pull(owner, "children");
  expect(stored).toMatchObject({ id: child, updated_at: atLimit, deleted_at: null });
});

it("still rejects malformed batch requests at the top level", async () => {
  const { push } = fixture();
  await expect(push(owner, { ...profile, id: "not-a-uuid" })).rejects.toThrow("Expected UUID");
  const tooMany = Array.from({ length: 21 }, (_, index) => ({
    ...profile,
    id: `77777777-7777-4777-8777-${String(index).padStart(12, "0")}`,
  }));
  await expect(push(owner, ...tooMany)).rejects.toThrow("Expected at most 20 changes");
});
