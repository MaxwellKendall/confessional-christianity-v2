import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

const fields = new Map([
  ["children", ["name", "age", "created_at", "active_catechism_id"]],
  ["catechism_assignments", ["catechism_slug", "started_at", "started_at_question"]],
  ["catechism_pacing", ["catechism_slug", "current_question"]],
  ["catechism_milestones", ["catechism_slug", "question", "state", "introduced_at", "review_count"]],
]);
const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const cursorPattern = /^(0|[1-9][0-9]{0,18})$/;
const maxCursor = 9223372036854775807n;
const pkForUser = (sub) => `account#${sub}`;
const pkForChild = (id) => `child#${id}`;
const pkForRecord = (table, id) => `record#${table}#${id}`;
const cursorKey = (table, cursor) => `change#${table}#${cursor.toString().padStart(19, "0")}`;
const denied = () => new Error("Not authorized for this sync record");

function uuid(value) {
  if (typeof value !== "string" || !uuidPattern.test(value)) throw new Error("Expected UUID");
  return value.toLowerCase();
}

function timestamp(value) {
  if (typeof value !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(value)) {
    throw new Error("Expected UTC timestamp");
  }
  const instant = Date.parse(value);
  if (!Number.isFinite(instant) || new Date(instant).toISOString().slice(0, 19) !== value.slice(0, 19)) {
    throw new Error("Expected UTC timestamp");
  }
  return new Date(instant).toISOString();
}

function parseChange(change) {
  const allowedKeys = ["id", "table", "row_id", "child_id", "updated_at", "deleted_at", "payload"];
  if (!change || Object.keys(change).some(key => !allowedKeys.includes(key))) throw new Error("Invalid sync input");
  const { table, payload } = change;
  const allowedFields = fields.get(table);
  if (!allowedFields) throw new Error("Unknown writable sync table");
  const id = uuid(change.row_id);
  const child_id = uuid(change.child_id);
  if (table === "children" && id !== child_id) throw new Error("Child row ID must match child ID");
  const deleted_at = change.deleted_at == null ? null : timestamp(change.deleted_at);
  if (deleted_at === null) {
    if (typeof payload !== "string" || Buffer.byteLength(payload) > 4096) throw new Error("Invalid sync payload");
    let body;
    try { body = JSON.parse(payload); } catch { throw new Error("Invalid sync payload"); }
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.entries(body).some(([key, value]) =>
          !allowedFields.includes(key) || (value !== null && !["string", "number", "boolean"].includes(typeof value)))) {
      throw new Error("Invalid sync payload fields");
    }
  } else if (payload != null) {
    throw new Error("Tombstones cannot contain a payload");
  }
  return {
    operation: uuid(change.id),
    record: { table, id, child_id, updated_at: timestamp(change.updated_at), deleted_at, payload: payload ?? null },
  };
}

const canAccess = (access, subject) =>
  access && !access.retired && (access.owner === subject || Object.values(access.guardians).includes(subject));

function write(pk, sk, current, value) {
  return { pk, sk, expected: current?.version, value };
}

async function applyChange(db, subject, record) {
  const childKey = pkForChild(record.child_id);
  const recordKey = pkForRecord(record.table, record.id);
  const accountKey = pkForUser(subject);

  for (let attempt = 0; attempt < 8; attempt++) {
    const [access, previous, disabled] = await Promise.all([
      db.get(childKey, "access"),
      db.get(recordKey, "value"),
      db.get(accountKey, "disabled"),
    ]);
    if (disabled || (previous && previous.record.child_id !== record.child_id)) throw denied();
    const creating = !access && !previous && record.table === "children" && !record.deleted_at;
    if (!creating && (!canAccess(access, subject) ||
        (record.table === "children" && record.deleted_at && access.owner !== subject))) throw denied();
    if (previous && previous.record.updated_at >= record.updated_at) return;

    const revision = randomUUID();
    const changes = [
      write(accountKey, "disabled", undefined),
      write(childKey, "access", access, creating ? { version: revision, owner: subject, guardians: {} } : undefined),
      write(recordKey, "value", previous, { version: revision, record }),
    ];
    if (creating) {
      changes.push(write(accountKey, `owned#${record.child_id}`, undefined, { version: revision }));
    }
    if (!previous) {
      changes.push(write(childKey, `row#${record.table}#${record.id}`, undefined, { version: revision }));
    }

    const recipients = creating ? [subject] : [...new Set([access.owner, ...Object.values(access.guardians)])];
    if (recipients.length > 9) throw new Error("Too many child guardians");
    const counters = await Promise.all(recipients.map(sub => db.get(pkForUser(sub), "sequence")));
    for (const [index, recipient] of recipients.entries()) {
      const pk = pkForUser(recipient);
      const counter = counters[index];
      const next = BigInt(counter?.sequence ?? "0") + 1n;
      if (next > maxCursor) throw new Error("Sync sequence exhausted");
      changes.push(
        write(pk, "sequence", counter, { sequence: next.toString(), version: revision }),
        write(pk, cursorKey(record.table, next), undefined, {
          version: revision, recordKey, childId: record.child_id, changeId: next.toString(),
        }),
      );
    }
    // A competing write, access change or account disable invalidates the entire transaction.
    if (await db.commit(changes)) return;
    await delay(Math.random() * Math.min(10 * 2 ** attempt, 250));
  }
  throw new Error("Sync write contention. Retry the push.");
}

async function pull(db, subject, { table, after = "0", limit = 50 }) {
  if (!fields.has(table) || typeof after !== "string" || !cursorPattern.test(after) ||
      BigInt(after) > maxCursor || !Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("Invalid sync page");
  }
  const accountKey = pkForUser(subject);
  if (await db.get(accountKey, "disabled")) throw denied();

  const highWater = (await db.get(accountKey, "sequence"))?.sequence ?? "0";
  const end = cursorKey(table, highWater);
  const page = [];
  let cursor = cursorKey(table, after);
  while (cursor < end && page.length < limit) {
    const entries = await db.query(accountKey, cursor, end, limit - page.length);
    if (entries.length === 0) break;
    cursor = entries.at(-1).sk;
    const records = await Promise.all(entries.map(async entry => {
      const row = await db.get(entry.recordKey, "value");
      if (row?.version !== entry.version) return null;
      const access = await db.get(pkForChild(entry.childId), "access");
      return canAccess(access, subject) ? { ...row.record, change_id: entry.changeId } : null;
    }));
    page.push(...records.filter(record => record !== null));
  }
  return page;
}

export function createHandler(db) {
  return async event => {
    const subject = event.identity?.sub;
    if (typeof subject !== "string" || !uuidPattern.test(subject)) throw denied();
    switch (event.info.fieldName) {
      case "pushSync": {
        const { changes } = event.arguments;
        if (!Array.isArray(changes) || changes.length > 20) throw new Error("Expected at most 20 changes");
        const validated = changes.map(parseChange);
        for (const { record } of validated) await applyChange(db, subject, record);
        return validated.map(({ operation }) => operation);
      }
      case "pullSync": return pull(db, subject, event.arguments);
      default: throw new Error("Unknown sync operation");
    }
  };
}
