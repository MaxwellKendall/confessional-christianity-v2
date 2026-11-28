import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

export const MAX_FUTURE_SKEW_MS = 24 * 60 * 60 * 1000;

const fields = new Map([
  ["children", ["name", "age", "created_at", "active_catechism_id"]],
  ["catechism_assignments", ["catechism_slug", "started_at", "started_at_question"]],
  ["catechism_pacing", ["catechism_slug", "current_question"]],
  ["catechism_milestones", ["catechism_slug", "question", "state", "introduced_at", "review_count"]],
  ["lords_day_notes", ["service_date", "passage_ref", "sermon_title", "preacher", "church", "extracted_text", "created_at"]],
  ["note_cards", ["kind", "body", "verse_ref", "attribution", "palette", "position", "edited_by_user", "created_at"]],
]);
const noteTables = new Set(["lords_day_notes", "note_cards"]);
const cardKinds = new Set(["key_point", "quote", "verse"]);
const maxPayloadBytes = (table) => (table === "lords_day_notes" ? 65536 : 4096);
const allowedChangeKeys = ["id", "table", "row_id", "child_id", "note_id", "updated_at", "deleted_at", "payload"];
const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const cursorPattern = /^(0|[1-9][0-9]{0,18})$/;
const dateOnlyPattern = /^\d{4}-\d\d-\d\d$/;
const maxCursor = 9223372036854775807n;
const pkForUser = (sub) => `account#${sub}`;
const pkForChild = (id) => `child#${id}`;
const pkForNote = (id) => `note#${id}`;
const pkForRecord = (table, id) => `record#${table}#${id}`;
const cursorKey = (table, cursor) => `change#${table}#${cursor.toString().padStart(19, "0")}`;
const denied = () => new Error("Not authorized for this sync record");
const acceptedResult = (id) => ({ id, status: "ACCEPTED", reason: null });
const rejectedResult = (id, reason) => ({ id, status: "REJECTED", reason });
const retryResult = (id, reason = "CONTENTION") => ({ id, status: "RETRY", reason });

function parseUuid(value) {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

function uuid(value) {
  const parsed = parseUuid(value);
  if (!parsed) throw new Error("Expected UUID");
  return parsed;
}

function parseTimestamp(value) {
  if (typeof value !== "string" ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(value)) {
    return null;
  }
  const instant = Date.parse(value);
  if (!Number.isFinite(instant) || new Date(instant).toISOString().slice(0, 19) !== value.slice(0, 19)) {
    return null;
  }
  return new Date(instant).toISOString();
}

function isValidDateOnly(value) {
  if (typeof value !== "string" || !dateOnlyPattern.test(value)) return false;
  const instant = Date.parse(`${value}T00:00:00.000Z`);
  return Number.isFinite(instant) && new Date(instant).toISOString().slice(0, 10) === value;
}

function validateTablePayload(table, body) {
  if (table === "lords_day_notes") {
    if (typeof body.service_date !== "string" ||
        (parseTimestamp(body.service_date) === null && !isValidDateOnly(body.service_date))) {
      return false;
    }
    if (body.created_at != null && parseTimestamp(body.created_at) === null) return false;
    for (const key of ["passage_ref", "sermon_title", "preacher", "church", "extracted_text"]) {
      if (body[key] != null && typeof body[key] !== "string") return false;
    }
    return true;
  }
  if (table === "note_cards") {
    if (typeof body.kind !== "string" || !cardKinds.has(body.kind)) return false;
    if (typeof body.position !== "number" || !Number.isInteger(body.position) || body.position < 0) return false;
    if (body.edited_by_user != null && typeof body.edited_by_user !== "boolean") return false;
    if (body.created_at != null && parseTimestamp(body.created_at) === null) return false;
    for (const key of ["attribution", "palette"]) {
      if (body[key] != null && typeof body[key] !== "string") return false;
    }
    if (body.kind === "verse") {
      if (typeof body.verse_ref !== "string" || body.verse_ref.trim().length === 0) return false;
      if (body.body != null && body.body !== "") return false;
    } else {
      if (typeof body.body !== "string") return false;
      if (body.verse_ref != null && typeof body.verse_ref !== "string") return false;
    }
    return true;
  }
  return true;
}

function parseChange(change, maxTimestampMs) {
  if (Object.keys(change).some(key => !allowedChangeKeys.includes(key))) return { reason: "INVALID_INPUT" };
  const { table, payload } = change;
  const allowedFields = fields.get(table);
  if (!allowedFields) return { reason: "INVALID_INPUT" };
  const id = parseUuid(change.row_id);
  if (!id) return { reason: "INVALID_INPUT" };

  let child_id = null;
  let note_id = null;
  if (noteTables.has(table)) {
    if (change.child_id != null) return { reason: "INVALID_INPUT" };
    note_id = parseUuid(change.note_id);
    if (!note_id) return { reason: "INVALID_INPUT" };
    if (table === "lords_day_notes" && id !== note_id) return { reason: "INVALID_INPUT" };
  } else {
    if (change.note_id != null) return { reason: "INVALID_INPUT" };
    child_id = parseUuid(change.child_id);
    if (!child_id) return { reason: "INVALID_INPUT" };
    if (table === "children" && id !== child_id) return { reason: "INVALID_INPUT" };
  }

  const updated_at = parseTimestamp(change.updated_at);
  if (updated_at === null) return { reason: "INVALID_INPUT" };
  const deleted_at = change.deleted_at == null ? null : parseTimestamp(change.deleted_at);
  if (change.deleted_at != null && deleted_at === null) return { reason: "INVALID_INPUT" };
  if (deleted_at === null) {
    if (typeof payload !== "string" || Buffer.byteLength(payload) > maxPayloadBytes(table)) {
      return { reason: "INVALID_INPUT" };
    }
    let body;
    try { body = JSON.parse(payload); } catch { return { reason: "INVALID_INPUT" }; }
    if (!body || typeof body !== "object" || Array.isArray(body) ||
        Object.entries(body).some(([key, value]) =>
          !allowedFields.includes(key) || (value !== null && !["string", "number", "boolean"].includes(typeof value)))) {
      return { reason: "INVALID_INPUT" };
    }
    if (!validateTablePayload(table, body)) return { reason: "INVALID_INPUT" };
  } else if (payload != null) {
    return { reason: "INVALID_INPUT" };
  }
  if (Date.parse(updated_at) > maxTimestampMs ||
      (deleted_at !== null && Date.parse(deleted_at) > maxTimestampMs)) {
    return { reason: "CLOCK_SKEW" };
  }
  return {
    record: { table, id, child_id, note_id, updated_at, deleted_at, payload: payload ?? null },
  };
}

const canAccess = (access, subject) =>
  Boolean(access && !access.retired && (access.owner === subject || Object.values(access.guardians).includes(subject)));

const canAccessNote = (access, subject) =>
  Boolean(access && !access.retired && access.owner === subject);

function write(pk, sk, current, value) {
  return { pk, sk, expected: current?.version, value };
}

async function applyNoteChange(db, subject, record, sleep) {
  const noteKey = pkForNote(record.note_id);
  const recordKey = pkForRecord(record.table, record.id);
  const accountKey = pkForUser(subject);

  for (let attempt = 0; attempt < 8; attempt++) {
    const [access, previous, disabled, counter] = await Promise.all([
      db.get(noteKey, "access"),
      db.get(recordKey, "value"),
      db.get(accountKey, "disabled"),
      db.get(accountKey, "sequence"),
    ]);
    if (disabled) throw denied();
    if (previous && previous.record.note_id !== record.note_id) {
      return { status: "REJECTED", reason: "UNAUTHORIZED" };
    }
    const creating = !access && !previous && record.table === "lords_day_notes" && !record.deleted_at;
    if (!creating && !canAccessNote(access, subject)) {
      return { status: "REJECTED", reason: "UNAUTHORIZED" };
    }
    if (previous && previous.record.updated_at >= record.updated_at) {
      return { status: "ACCEPTED", reason: null };
    }

    const revision = randomUUID();
    const next = BigInt(counter?.sequence ?? "0") + 1n;
    if (next > maxCursor) throw new Error("Sync sequence exhausted");
    const changes = [
      write(accountKey, "disabled", undefined),
      write(noteKey, "access", access, creating ? { version: revision, owner: subject } : undefined),
      write(recordKey, "value", previous, { version: revision, record }),
      write(accountKey, "sequence", counter, { sequence: next.toString(), version: revision }),
      write(accountKey, cursorKey(record.table, next), undefined, {
        version: revision, recordKey, noteId: record.note_id, changeId: next.toString(),
      }),
    ];
    if (creating) {
      changes.push(write(accountKey, `owned_note#${record.note_id}`, undefined, { version: revision }));
    }
    if (!previous) {
      changes.push(write(noteKey, `row#${record.table}#${record.id}`, undefined, { version: revision }));
    }
    if (await db.commit(changes)) return { status: "ACCEPTED", reason: null };
    await sleep(Math.random() * Math.min(10 * 2 ** attempt, 250));
  }
  return { status: "RETRY", reason: "CONTENTION" };
}

async function applyChange(db, subject, record, sleep) {
  if (noteTables.has(record.table)) {
    return applyNoteChange(db, subject, record, sleep);
  }
  const childKey = pkForChild(record.child_id);
  const recordKey = pkForRecord(record.table, record.id);
  const accountKey = pkForUser(subject);

  for (let attempt = 0; attempt < 8; attempt++) {
    const [access, previous, disabled] = await Promise.all([
      db.get(childKey, "access"),
      db.get(recordKey, "value"),
      db.get(accountKey, "disabled"),
    ]);
    if (disabled) throw denied();
    if (previous && previous.record.child_id !== record.child_id) {
      return { status: "REJECTED", reason: "UNAUTHORIZED" };
    }
    const creating = !access && !previous && record.table === "children" && !record.deleted_at;
    if (!creating && !canAccess(access, subject)) {
      return { status: "REJECTED", reason: "UNAUTHORIZED" };
    }
    if (record.deleted_at && access.owner !== subject) {
      // Only the owner may remove a whole child. A co-guardian's removal sends the profile
      // tombstone first, then its progress tombstones with the same deleted_at: remember the
      // refused removal so none of its progress tombstones apply, in this batch or a later one.
      const deniedKey = `removal_denied#${subject}`;
      if (record.table === "children") {
        const denied = await db.get(childKey, deniedKey);
        if (denied?.deleted_at !== record.deleted_at) {
          await db.commit([write(childKey, deniedKey, denied, { version: randomUUID(), deleted_at: record.deleted_at })]);
        }
        return { status: "REJECTED", reason: "UNAUTHORIZED" };
      }
      const denied = await db.get(childKey, deniedKey);
      if (denied?.deleted_at === record.deleted_at) {
        return { status: "REJECTED", reason: "UNAUTHORIZED" };
      }
    }
    if (previous && previous.record.updated_at >= record.updated_at) {
      return { status: "ACCEPTED", reason: null };
    }

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
    if (await db.commit(changes)) return { status: "ACCEPTED", reason: null };
    await sleep(Math.random() * Math.min(10 * 2 ** attempt, 250));
  }
  return { status: "RETRY", reason: "CONTENTION" };
}

async function pull(db, subject, { table, after = "0", limit = 50 }) {
  if (!fields.has(table) || typeof after !== "string" || !cursorPattern.test(after) ||
      BigInt(after) > maxCursor || !Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("Invalid sync page");
  }
  const accountKey = pkForUser(subject);
  if (await db.get(accountKey, "disabled")) throw denied();

  const isNoteTable = noteTables.has(table);
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
      if (isNoteTable) {
        const access = await db.get(pkForNote(entry.noteId), "access");
        return canAccessNote(access, subject) ? { ...row.record, change_id: entry.changeId } : null;
      }
      const access = await db.get(pkForChild(entry.childId), "access");
      return canAccess(access, subject) ? { ...row.record, change_id: entry.changeId } : null;
    }));
    page.push(...records.filter(record => record !== null));
  }
  return page;
}

export function createHandler(db, { now = Date.now, sleep = delay, maxFutureSkewMs = MAX_FUTURE_SKEW_MS } = {}) {
  return async event => {
    const subject = event.identity?.sub;
    if (typeof subject !== "string" || !uuidPattern.test(subject)) throw denied();
    switch (event.info.fieldName) {
      case "pushSync": {
        const { changes } = event.arguments;
        if (!Array.isArray(changes) || changes.length > 20) throw new Error("Expected at most 20 changes");
        const items = changes.map(change => {
          if (!change || typeof change !== "object") throw new Error("Invalid sync input");
          return { operation: uuid(change.id), change };
        });
        if (await db.get(pkForUser(subject), "disabled")) throw denied();
        const maxTimestampMs = now() + maxFutureSkewMs;
        const results = [];
        for (let index = 0; index < items.length; index++) {
          const { operation, change } = items[index];
          const parsed = parseChange(change, maxTimestampMs);
          if (parsed.reason) {
            results.push(rejectedResult(operation, parsed.reason));
            continue;
          }
          const outcome = await applyChange(db, subject, parsed.record, sleep);
          results.push(outcome.status === "ACCEPTED"
            ? acceptedResult(operation)
            : outcome.status === "REJECTED"
              ? rejectedResult(operation, outcome.reason)
              : retryResult(operation, outcome.reason));
          if (outcome.status === "RETRY") {
            for (let rest = index + 1; rest < items.length; rest++) {
              results.push(retryResult(items[rest].operation, outcome.reason));
            }
            break;
          }
        }
        return results;
      }
      case "pullSync": return pull(db, subject, event.arguments);
      default: throw new Error("Unknown sync operation");
    }
  };
}
