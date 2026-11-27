// TKL-1071: Account deletion cleanup hook invoked by studio-platform's DeleteAccount Lambda
// with { sub, product: "confessional" }. Implements the 5-step resumable contract in infra/SYNC.md:
// 1. Set account#<sub>/disabled first (with version) and retain it permanently.
// 2. Retire and purge every owned child's rows, catalog entries and co-guardian reverse member# entries,
//    then strip owner/guardians from child#<id>/access and delete owned#<id>.
// 3. Retire and purge every owned Lord's Day note and its cards, then strip owner from note#<id>/access
//    and delete owned_note#<id>.
// 4. Atomically remove departing sub from other owners' child#<id>/access.guardians and delete member#<id>.
// 5. Purge account#<sub>/change#* references and delete account#<sub>/sequence.
import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";

const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const MAX_ATTEMPTS = 8;

const pkForUser = (sub) => `account#${sub}`;
const pkForChild = (id) => `child#${id}`;
const pkForNote = (id) => `note#${id}`;
const pkForRecord = (table, id) => `record#${table}#${id}`;

function stripKeys(item) {
  const copy = { ...item };
  delete copy.pk;
  delete copy.sk;
  return copy;
}

async function backoff(sleep, attempt) {
  await sleep(Math.random() * Math.min(10 * 2 ** attempt, 250));
}

async function ensureDisabled(db, accountKey) {
  if (await db.get(accountKey, "disabled")) return;
  const wrote = await db.putConditional(accountKey, "disabled", undefined, { version: randomUUID() });
  if (!wrote && !(await db.get(accountKey, "disabled"))) {
    throw new Error("Failed to set account disabled marker");
  }
}

async function deleteCatalogRows(db, containerPk) {
  const rows = await db.queryPrefix(containerPk, "row#");
  for (const row of rows) {
    const rest = row.sk.slice("row#".length);
    const sep = rest.indexOf("#");
    if (sep > 0) {
      const table = rest.slice(0, sep);
      const rowId = rest.slice(sep + 1);
      await db.remove(pkForRecord(table, rowId), "value");
    }
    await db.remove(containerPk, row.sk);
  }
}

async function retireOwnedAccess(db, containerPk, subject, kind, id, sleep) {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const access = await db.get(containerPk, "access");
    if (!access) return { state: "missing" };
    if (access.retired === true && access.owner === undefined) {
      return { state: "finalized", access };
    }
    if (access.owner !== subject) {
      throw new Error(`Ownership mismatch for ${kind} ${id}`);
    }
    if (access.retired === true) {
      return { state: "retired", access };
    }
    const next = { ...stripKeys(access), version: randomUUID(), retired: true };
    if (await db.putConditional(containerPk, "access", access.version, next)) {
      return { state: "retired", access: { pk: containerPk, sk: "access", ...next } };
    }
    await backoff(sleep, attempt);
  }
  throw new Error(`Contention retiring ${kind} ${id}`);
}

async function finalizeRetiredAccess(db, containerPk, kind, id, sleep) {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const access = await db.get(containerPk, "access");
    if (!access) return;
    if (access.retired === true && access.owner === undefined && access.guardians === undefined) {
      return;
    }
    if (await db.putConditional(containerPk, "access", access.version, { version: randomUUID(), retired: true })) {
      return;
    }
    await backoff(sleep, attempt);
  }
  throw new Error(`Contention finalizing ${kind} ${id}`);
}

async function deleteOwnedChildren(db, accountKey, subject, sleep) {
  const owned = await db.queryPrefix(accountKey, "owned#");
  for (const entry of owned) {
    const childId = entry.sk.slice("owned#".length);
    const childKey = pkForChild(childId);
    const retired = await retireOwnedAccess(db, childKey, subject, "child", childId, sleep);

    if (retired.state === "retired") {
      await deleteCatalogRows(db, childKey);
      const guardians = [...new Set(Object.values(retired.access.guardians ?? {}))];
      for (const guardianSub of guardians) {
        await db.remove(pkForUser(guardianSub), `member#${childId}`);
      }
      await finalizeRetiredAccess(db, childKey, "child", childId, sleep);
    } else if (retired.state === "finalized") {
      await deleteCatalogRows(db, childKey);
    }

    await db.remove(accountKey, entry.sk);
  }
}

async function deleteOwnedNotes(db, accountKey, subject, sleep) {
  const owned = await db.queryPrefix(accountKey, "owned_note#");
  for (const entry of owned) {
    const noteId = entry.sk.slice("owned_note#".length);
    const noteKey = pkForNote(noteId);
    const retired = await retireOwnedAccess(db, noteKey, subject, "note", noteId, sleep);

    if (retired.state === "retired") {
      await deleteCatalogRows(db, noteKey);
      await finalizeRetiredAccess(db, noteKey, "note", noteId, sleep);
    } else if (retired.state === "finalized") {
      await deleteCatalogRows(db, noteKey);
    }

    await db.remove(accountKey, entry.sk);
  }
}

async function removeMemberships(db, accountKey, subject, sleep) {
  const memberships = await db.queryPrefix(accountKey, "member#");
  for (const entry of memberships) {
    const childId = entry.sk.slice("member#".length);
    const childKey = pkForChild(childId);
    let done = false;

    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      const access = await db.get(childKey, "access");
      if (!access || access.retired) {
        await db.remove(accountKey, entry.sk);
        done = true;
        break;
      }
      const currentGuardians = access.guardians ?? {};
      const remainingEntries = Object.entries(currentGuardians).filter(([, sub]) => sub !== subject);
      if (remainingEntries.length === Object.keys(currentGuardians).length) {
        await db.remove(accountKey, entry.sk);
        done = true;
        break;
      }
      const updated = {
        ...stripKeys(access),
        version: randomUUID(),
        guardians: Object.fromEntries(remainingEntries),
      };
      const committed = await db.commit([
        { pk: childKey, sk: "access", expected: access.version, value: updated },
        { pk: accountKey, sk: entry.sk, del: true },
      ]);
      if (committed) {
        done = true;
        break;
      }
      await backoff(sleep, attempt);
    }

    if (!done) {
      throw new Error(`Contention removing membership for child ${childId}`);
    }
  }
}

async function purgeStream(db, accountKey) {
  const changes = await db.queryPrefix(accountKey, "change#");
  for (const entry of changes) {
    await db.remove(accountKey, entry.sk);
  }
  await db.remove(accountKey, "sequence");
}

export function createDeleteHandler(db, { sleep = delay } = {}) {
  return async (event) => {
    const subject = event?.sub;
    if (typeof subject !== "string" || !uuidPattern.test(subject)) {
      throw new Error("Invalid subject");
    }
    if (event?.product !== undefined && event.product !== "confessional") {
      throw new Error(`Unexpected product: ${event.product}`);
    }

    const accountKey = pkForUser(subject);
    // Step 1: disable account before enumerating data so in-flight pushes/pulls stop immediately.
    await ensureDisabled(db, accountKey);
    // Step 2: retire and purge owned children, their rows and co-guardian reverse memberships.
    await deleteOwnedChildren(db, accountKey, subject, sleep);
    // Step 3: retire and purge owned Lord's Day notes and their cards.
    await deleteOwnedNotes(db, accountKey, subject, sleep);
    // Step 4: remove departing subject from other owners' children atomically with member# entries.
    await removeMemberships(db, accountKey, subject, sleep);
    // Step 5: purge departing subject's change stream and sequence (keep disabled marker).
    await purgeStream(db, accountKey);

    return { ok: true, sub: subject };
  };
}
