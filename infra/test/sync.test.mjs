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

// TKL-1069 / TKL-905: private Lord's Day notes and cards

const noteId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const secondNoteId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const cardId = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const secondCardId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const thirdCardId = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

const notePayload = {
  service_date: "2026-11-22T05:00:00.000Z",
  passage_ref: "Romans 8:28-30",
  sermon_title: "The Golden Chain",
  preacher: "Rev. Smith",
  church: "Grace Presbyterian",
  extracted_text: "All things work together for good.",
  created_at: stamp,
};

const noteChange = {
  id: operation,
  table: "lords_day_notes",
  row_id: noteId,
  note_id: noteId,
  updated_at: stamp,
  payload: JSON.stringify(notePayload),
};

const keyPointCard = {
  id: secondOperation,
  table: "note_cards",
  row_id: cardId,
  note_id: noteId,
  updated_at: stamp,
  payload: JSON.stringify({
    kind: "key_point",
    body: "God's purpose decides what is good.",
    verse_ref: null,
    attribution: null,
    palette: "chapel",
    position: 0,
    edited_by_user: false,
    created_at: stamp,
  }),
};

const quoteCard = {
  id: thirdOperation,
  table: "note_cards",
  row_id: secondCardId,
  note_id: noteId,
  updated_at: stamp,
  payload: JSON.stringify({
    kind: "quote",
    body: "No weak link in the golden chain.",
    verse_ref: null,
    attribution: "Rev. Smith",
    palette: "gilt",
    position: 1,
    edited_by_user: true,
    created_at: stamp,
  }),
};

const verseCard = {
  id: "99999999-9999-4999-8999-999999999998",
  table: "note_cards",
  row_id: thirdCardId,
  note_id: noteId,
  updated_at: stamp,
  payload: JSON.stringify({
    kind: "verse",
    body: "",
    verse_ref: "Rom.8.28",
    attribution: null,
    palette: "moss",
    position: 2,
    edited_by_user: false,
    created_at: stamp,
  }),
};

it("round-trips private Lord's Day notes and cards preserving all fields and enforcing card validation", async () => {
  const { push, pull } = fixture();

  // Creating a note and its three card kinds in one batch preserves order and all fields.
  await expect(push(owner, noteChange, keyPointCard, quoteCard, verseCard)).resolves.toEqual([
    accepted(operation),
    accepted(secondOperation),
    accepted(thirdOperation),
    accepted(verseCard.id),
  ]);

  const notes = await pull(owner, "lords_day_notes");
  expect(notes).toHaveLength(1);
  expect(notes[0]).toMatchObject({
    table: "lords_day_notes",
    id: noteId,
    child_id: null,
    note_id: noteId,
    updated_at: stamp,
    deleted_at: null,
    change_id: "1",
  });
  expect(JSON.parse(notes[0].payload)).toEqual(notePayload);

  const cards = await pull(owner, "note_cards");
  expect(cards).toHaveLength(3);
  expect(cards.map(c => c.id)).toEqual([cardId, secondCardId, thirdCardId]);
  expect(cards.map(c => c.change_id)).toEqual(["2", "3", "4"]);
  expect(cards.every(c => c.note_id === noteId && c.child_id === null)).toBe(true);
  expect(JSON.parse(cards[0].payload)).toMatchObject({
    kind: "key_point", body: "God's purpose decides what is good.", palette: "chapel", position: 0, edited_by_user: false,
  });
  expect(JSON.parse(cards[1].payload)).toMatchObject({
    kind: "quote", attribution: "Rev. Smith", palette: "gilt", position: 1, edited_by_user: true,
  });
  expect(JSON.parse(cards[2].payload)).toMatchObject({
    kind: "verse", body: "", verse_ref: "Rom.8.28", palette: "moss", position: 2, edited_by_user: false,
  });

  // Card kind must be strictly key_point, quote or verse; verse must have verse_ref and no body.
  await expect(push(owner,
    { ...keyPointCard, id: operation, updated_at: later, payload: JSON.stringify({ kind: "summary", body: "x", position: 0, edited_by_user: false, created_at: stamp }) },
    { ...verseCard, id: secondOperation, updated_at: later, payload: JSON.stringify({ kind: "verse", body: "words not allowed", verse_ref: "Rom.8.28", position: 2, edited_by_user: false, created_at: stamp }) },
    { ...verseCard, id: thirdOperation, updated_at: later, payload: JSON.stringify({ kind: "verse", body: "", verse_ref: "  ", position: 2, edited_by_user: false, created_at: stamp }) },
  )).resolves.toEqual([
    rejected("INVALID_INPUT", operation),
    rejected("INVALID_INPUT", secondOperation),
    rejected("INVALID_INPUT", thirdOperation),
  ]);

  // Photos and disallowed fields are rejected; multi-page extracted_text up to 64 KiB is accepted.
  const longText = "a".repeat(8000);
  await expect(push(owner,
    { ...noteChange, id: operation, updated_at: later, payload: JSON.stringify({ ...notePayload, photo: "base64..." }) },
    { ...noteChange, id: secondOperation, updated_at: later, payload: JSON.stringify({ ...notePayload, extracted_text: longText }) },
    { ...noteChange, id: thirdOperation, updated_at: later, payload: JSON.stringify({ ...notePayload, extracted_text: "x".repeat(70000) }) },
  )).resolves.toEqual([
    rejected("INVALID_INPUT", operation),
    accepted(secondOperation),
    rejected("INVALID_INPUT", thirdOperation),
  ]);

  // Envelope validation: child_id disallowed on note tables, note_id disallowed on child tables, note row_id === note_id.
  await expect(push(owner,
    { ...noteChange, id: operation, child_id: child, updated_at: later },
    { ...noteChange, id: secondOperation, row_id: secondNoteId, note_id: noteId, updated_at: later },
    { ...profile, id: thirdOperation, note_id: noteId },
  )).resolves.toEqual([
    rejected("INVALID_INPUT", operation),
    rejected("INVALID_INPUT", secondOperation),
    rejected("INVALID_INPUT", thirdOperation),
  ]);
});

it("scopes Lord's Day notes and cards strictly to the verified Cognito subject and rejects forged ownership or parent IDs", async () => {
  const { push, pull } = fixture();

  // Unauthenticated caller rejected.
  await expect(push(undefined, noteChange)).rejects.toThrow("Not authorized");

  // Card write without an existing owned parent note is rejected.
  await expect(push(owner, keyPointCard)).resolves.toEqual([rejected("UNAUTHORIZED", secondOperation)]);

  // Forged ownership attributes are rejected.
  await expect(push(owner, { ...noteChange, owner_sub: stranger })).resolves.toEqual([rejected("INVALID_INPUT")]);
  await expect(push(owner, { ...noteChange, payload: JSON.stringify({ ...notePayload, user_id: stranger }) }))
    .resolves.toEqual([rejected("INVALID_INPUT")]);
  await expect(push(owner, { ...keyPointCard, payload: JSON.stringify({ kind: "key_point", body: "x", position: 0, owner_sub: stranger }) }))
    .resolves.toEqual([rejected("INVALID_INPUT", secondOperation)]);

  // Owner creates note and card.
  await expect(push(owner, noteChange, keyPointCard)).resolves.toEqual([accepted(operation), accepted(secondOperation)]);

  // Unrelated account cannot list/read, update, attach cards to, or delete owner's note or card.
  await expect(pull(stranger, "lords_day_notes")).resolves.toEqual([]);
  await expect(pull(stranger, "note_cards")).resolves.toEqual([]);
  await expect(push(stranger,
    { ...noteChange, id: operation, updated_at: later },
    { ...noteChange, id: secondOperation, payload: null, updated_at: later, deleted_at: later },
    { ...keyPointCard, id: thirdOperation, updated_at: later },
    { ...keyPointCard, id: "99999999-9999-4999-8999-999999999991", row_id: secondCardId, updated_at: later },
    { ...keyPointCard, id: "99999999-9999-4999-8999-999999999992", payload: null, updated_at: later, deleted_at: later },
  )).resolves.toEqual([
    rejected("UNAUTHORIZED", operation),
    rejected("UNAUTHORIZED", secondOperation),
    rejected("UNAUTHORIZED", thirdOperation),
    rejected("UNAUTHORIZED", "99999999-9999-4999-8999-999999999991"),
    rejected("UNAUTHORIZED", "99999999-9999-4999-8999-999999999992"),
  ]);

  // Owner cannot re-parent an existing card UUID onto a different note (even one they own).
  const secondNote = { ...noteChange, id: operation, row_id: secondNoteId, note_id: secondNoteId };
  await expect(push(owner, secondNote)).resolves.toEqual([accepted(operation)]);
  await expect(push(owner, { ...keyPointCard, id: secondOperation, note_id: secondNoteId, updated_at: later }))
    .resolves.toEqual([rejected("UNAUTHORIZED", secondOperation)]);

  // Stranger's own note stays isolated from owner.
  const strangerNoteId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
  await expect(push(stranger, { ...noteChange, id: operation, row_id: strangerNoteId, note_id: strangerNoteId }))
    .resolves.toEqual([accepted(operation)]);
  expect((await pull(owner, "lords_day_notes")).map(n => n.id)).toEqual([noteId, secondNoteId]);
  expect((await pull(stranger, "lords_day_notes")).map(n => n.id)).toEqual([strangerNoteId]);
});

it("handles stale writes, soft deletes, replay, ordering and server-assigned change_id paging for notes and cards", async () => {
  const { push, pull } = fixture();
  const secondNote = { ...noteChange, id: secondOperation, row_id: secondNoteId, note_id: secondNoteId };

  await expect(push(owner, noteChange, secondNote, keyPointCard, quoteCard)).resolves.toEqual([
    accepted(operation), accepted(secondOperation), accepted(secondOperation), accepted(thirdOperation),
  ]);

  // Replay and stale writes are acknowledged without advancing change_id.
  await expect(push(owner,
    noteChange,
    { ...noteChange, id: secondOperation, updated_at: "2025-01-01T00:00:00.000Z" },
    { ...keyPointCard, id: thirdOperation, updated_at: "2025-01-01T00:00:00.000Z" },
  )).resolves.toEqual([accepted(operation), accepted(secondOperation), accepted(thirdOperation)]);

  // Paging strictly after change_id across both tables.
  const [n1] = await pull(owner, "lords_day_notes", "0", 1);
  const [n2] = await pull(owner, "lords_day_notes", n1.change_id, 1);
  expect([n1.id, n2.id]).toEqual([noteId, secondNoteId]);
  expect([n1.change_id, n2.change_id]).toEqual(["1", "2"]);
  await expect(pull(owner, "lords_day_notes", n2.change_id)).resolves.toEqual([]);

  const [c1] = await pull(owner, "note_cards", "0", 1);
  const [c2] = await pull(owner, "note_cards", c1.change_id, 1);
  expect([c1.id, c2.id]).toEqual([cardId, secondCardId]);
  expect([c1.change_id, c2.change_id]).toEqual(["3", "4"]);
  await expect(pull(owner, "note_cards", c2.change_id)).resolves.toEqual([]);

  // Soft deletes travel as tombstones with payload: null; tombstone with payload is rejected.
  await expect(push(owner,
    { ...keyPointCard, id: operation, payload: JSON.stringify({ kind: "key_point", body: "x", position: 0 }), updated_at: later, deleted_at: later },
    { ...keyPointCard, id: secondOperation, payload: null, updated_at: later, deleted_at: later },
    { ...noteChange, id: thirdOperation, payload: null, updated_at: later, deleted_at: later },
  )).resolves.toEqual([
    rejected("INVALID_INPUT", operation),
    accepted(secondOperation),
    accepted(thirdOperation),
  ]);

  await expect(pull(owner, "note_cards", c2.change_id)).resolves.toMatchObject([
    { id: cardId, note_id: noteId, deleted_at: later, payload: null, change_id: "5" },
  ]);
  await expect(pull(owner, "lords_day_notes", n2.change_id)).resolves.toMatchObject([
    { id: noteId, note_id: noteId, deleted_at: later, payload: null, change_id: "6" },
  ]);
});

it("records ownership and row catalog entries for account deletion and blocks retired notes and disabled accounts", async () => {
  const { db, push, pull } = fixture();
  await expect(push(owner, noteChange, keyPointCard)).resolves.toEqual([accepted(operation), accepted(secondOperation)]);

  // Account deletion index and note row catalog entries exist.
  await expect(db.get(`account#${owner}`, `owned_note#${noteId}`)).resolves.toBeDefined();
  await expect(db.get(`note#${noteId}`, `row#lords_day_notes#${noteId}`)).resolves.toBeDefined();
  await expect(db.get(`note#${noteId}`, `row#note_cards#${cardId}`)).resolves.toBeDefined();

  // Retiring note access invalidates writes and hides both note and card from pull.
  const access = await db.get(`note#${noteId}`, "access");
  await db.commit([{ pk: `note#${noteId}`, sk: "access", expected: access.version, value: { version: "retired", retired: true } }]);
  await expect(pull(owner, "lords_day_notes")).resolves.toEqual([]);
  await expect(pull(owner, "note_cards")).resolves.toEqual([]);
  await expect(push(owner, { ...noteChange, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED")]);
  await expect(push(owner, { ...keyPointCard, updated_at: later })).resolves.toEqual([rejected("UNAUTHORIZED", secondOperation)]);

  // Disabling the account blocks push and pull for both tables.
  await db.commit([{ pk: `account#${owner}`, sk: "disabled", value: { version: "disabled" } }]);
  await expect(pull(owner, "lords_day_notes")).rejects.toThrow("Not authorized");
  await expect(pull(owner, "note_cards")).rejects.toThrow("Not authorized");
  await expect(push(owner, { ...noteChange, row_id: secondNoteId, note_id: secondNoteId })).rejects.toThrow("Not authorized");
});

it("refuses a co-guardian's whole-child removal without touching the profile or its progress", async () => {
  const { push, pull, grant } = fixture();
  await expect(push(owner, profile)).resolves.toEqual([accepted()]);
  await expect(push(owner, { ...assignment, id: secondOperation })).resolves.toEqual([accepted(secondOperation)]);
  await expect(push(owner, { ...assignment, id: thirdOperation, row_id: secondProgress, table: "catechism_pacing",
    payload: JSON.stringify({ catechism_slug: "shorter", current_question: 4 }) }))
    .resolves.toEqual([accepted(thirdOperation)]);
  grant();

  // The app sends the profile tombstone first, then the progress tombstones of the same removal,
  // possibly in a later batch.
  const removedAt = later;
  const tombstone = { payload: null, updated_at: removedAt, deleted_at: removedAt };
  await expect(push(guardian, { ...profile, ...tombstone }, { ...assignment, ...tombstone, id: secondOperation }))
    .resolves.toEqual([rejected("UNAUTHORIZED"), rejected("UNAUTHORIZED", secondOperation)]);
  await expect(push(guardian, { ...assignment, ...tombstone, id: thirdOperation, row_id: secondProgress,
    table: "catechism_pacing" })).resolves.toEqual([rejected("UNAUTHORIZED", thirdOperation)]);

  // The owner still pulls a live profile and live progress, with no tombstone published.
  await expect(pull(owner, "children")).resolves.toMatchObject([{ id: child, deleted_at: null }]);
  await expect(pull(owner, "catechism_assignments")).resolves.toMatchObject([{ id: progress, deleted_at: null }]);
  await expect(pull(owner, "catechism_pacing")).resolves.toMatchObject([{ id: secondProgress, deleted_at: null }]);

  // A co-guardian's own later row-level tombstone (e.g. clearing progress) still applies.
  const unmarkAt = "2026-11-21T10:02:00.000Z";
  await expect(push(guardian, { ...assignment, payload: null, updated_at: unmarkAt, deleted_at: unmarkAt }))
    .resolves.toEqual([accepted()]);

  // The owner can still remove the child and its progress.
  const ownerAt = "2026-11-21T10:03:00.000Z";
  const ownerTombstone = { payload: null, updated_at: ownerAt, deleted_at: ownerAt };
  await expect(push(owner, { ...profile, ...ownerTombstone },
    { ...assignment, ...ownerTombstone, id: secondOperation, row_id: secondProgress, table: "catechism_pacing" }))
    .resolves.toEqual([accepted(), accepted(secondOperation)]);
});
