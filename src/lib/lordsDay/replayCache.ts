import { createHash, randomUUID } from 'crypto';
import { mkdir, readdir, readFile, rename, stat, unlink, writeFile } from 'fs/promises';
import { join } from 'path';

import type { DraftCard } from './cards';
import type { PageInput } from './gemini';

// Per-account replay cache for generated Lord's Day pages (TKL-940).
// Once a page has been generated, a retry returns that exact same page — cards
// and stable sourceKeys included — instead of calling Gemini again, so new
// wording or reordered output can't duplicate cards the person already reviewed.
// Keyed only by a SHA-256 digest of (account sub, model, page input, metadata):
// no photo bytes are retained in memory or on disk, and failed pages are never
// cached. When `dir` is provided, entries are also persisted atomically on disk
// so retries survive process restarts, in-memory eviction, and multi-day gaps
// across the life of a pending review.

export const DEFAULT_REPLAY_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const HEX_SHA256 = /^[a-f0-9]{64}$/;

export type CachedPageCard = Omit<DraftCard, 'id' | 'page'> & { sourceKey: string };

export interface CachedPage {
  generationId: string;
  extractedText: string;
  rejected: number;
  cards: CachedPageCard[];
}

export interface PageReplayCache {
  /** Looks up an already-generated page (awaiting any matching in-flight generation) without calling the generator. */
  get: (key: string) => Promise<CachedPage | null>;
  getOrCreate: (
    key: string,
    produce: () => Promise<{ page: CachedPage; costUsd: number }>,
  ) => Promise<{ page: CachedPage; costUsd: number; hit: boolean }>;
}

interface StoredEntry {
  storedAt: number;
  page: CachedPage;
}

export const pageReplayKey = ({
  sub,
  model,
  input,
  passage,
  title,
  preacher,
}: {
  sub: string;
  model: string;
  input: PageInput;
  passage?: string;
  title?: string;
  preacher?: string;
}): string => {
  const hash = createHash('sha256');
  hash.update(sub);
  hash.update('\0');
  hash.update(model);
  hash.update('\0');
  hash.update(passage ?? '');
  hash.update('\0');
  hash.update(title ?? '');
  hash.update('\0');
  hash.update(preacher ?? '');
  hash.update('\0');
  hash.update(input.kind);
  hash.update('\0');
  if (input.kind === 'image') {
    hash.update(input.mimeType);
    hash.update('\0');
    hash.update(input.data);
  } else {
    hash.update(input.text);
  }
  return hash.digest('hex');
};

const isStoredEntry = (value: unknown): value is StoredEntry => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const { storedAt, page } = value as Record<string, unknown>;
  if (typeof storedAt !== 'number' || !Number.isFinite(storedAt)) return false;
  if (!page || typeof page !== 'object' || Array.isArray(page)) return false;
  const { generationId, extractedText, rejected, cards } = page as Record<string, unknown>;
  return (
    typeof generationId === 'string' &&
    generationId.length > 0 &&
    typeof extractedText === 'string' &&
    typeof rejected === 'number' &&
    Array.isArray(cards)
  );
};

export const createPageReplayCache = ({
  dir,
  ttlMs = DEFAULT_REPLAY_TTL_MS,
  maxEntries = 500,
  maxDiskEntries = 5000,
  now = Date.now,
}: {
  /** Optional directory for atomic file-per-key persistence across process lifetimes. */
  dir?: string;
  ttlMs?: number;
  maxEntries?: number;
  maxDiskEntries?: number;
  now?: () => number;
} = {}): PageReplayCache => {
  const entries = new Map<string, StoredEntry>();
  const inFlight = new Map<string, Promise<{ page: CachedPage; costUsd: number; hit: boolean }>>();

  const diskPath = (key: string): string | null => {
    if (!dir || !HEX_SHA256.test(key)) return null;
    return join(dir, `${key}.json`);
  };

  const pruneMemory = (t: number) => {
    for (const [k, entry] of entries) {
      if (t - entry.storedAt >= ttlMs) entries.delete(k);
    }
    while (entries.size > maxEntries) {
      const oldest = entries.keys().next().value;
      if (oldest === undefined) break;
      entries.delete(oldest);
    }
  };

  const readDisk = async (key: string, t: number): Promise<StoredEntry | null> => {
    const file = diskPath(key);
    if (!file) return null;
    try {
      const raw = await readFile(file, 'utf8');
      const parsed: unknown = JSON.parse(raw);
      if (!isStoredEntry(parsed)) {
        await unlink(file).catch(() => undefined);
        return null;
      }
      if (t - parsed.storedAt >= ttlMs) {
        await unlink(file).catch(() => undefined);
        return null;
      }
      return parsed;
    } catch {
      return null;
    }
  };

  const pruneDisk = async () => {
    if (!dir) return;
    try {
      const names = (await readdir(dir)).filter((name) => name.endsWith('.json'));
      if (names.length <= maxDiskEntries) return;
      const stats = await Promise.all(
        names.map(async (name) => {
          const full = join(dir, name);
          try {
            const info = await stat(full);
            return { full, mtimeMs: info.mtimeMs };
          } catch {
            return null;
          }
        }),
      );
      const valid = stats.filter((s): s is { full: string; mtimeMs: number } => s !== null);
      valid.sort((a, b) => a.mtimeMs - b.mtimeMs);
      const excess = valid.length - maxDiskEntries;
      for (let i = 0; i < excess; i += 1) {
        await unlink(valid[i].full).catch(() => undefined);
      }
    } catch {
      // Disk pruning is best-effort; never fail a request over it.
    }
  };

  const writeDisk = async (key: string, entry: StoredEntry) => {
    const file = diskPath(key);
    if (!file || !dir) return;
    const tmp = `${file}.${process.pid}.${randomUUID()}.tmp`;
    try {
      await mkdir(dir, { recursive: true, mode: 0o700 });
      await writeFile(tmp, JSON.stringify(entry), { encoding: 'utf8', mode: 0o600 });
      await rename(tmp, file);
      await pruneDisk();
    } catch {
      await unlink(tmp).catch(() => undefined);
    }
  };

  const getFromMemory = (key: string, t: number): CachedPage | null => {
    const existing = entries.get(key);
    if (!existing) return null;
    if (t - existing.storedAt < ttlMs) {
      entries.delete(key);
      entries.set(key, existing);
      return existing.page;
    }
    entries.delete(key);
    return null;
  };

  return {
    async get(key) {
      const t = now();
      const mem = getFromMemory(key, t);
      if (mem) return mem;

      const pending = inFlight.get(key);
      if (pending) {
        try {
          return (await pending).page;
        } catch {
          return null;
        }
      }

      const disk = await readDisk(key, t);
      if (!disk) return null;
      entries.delete(key);
      entries.set(key, disk);
      pruneMemory(t);
      return disk.page;
    },

    async getOrCreate(key, produce) {
      const t = now();
      const mem = getFromMemory(key, t);
      if (mem) return { page: mem, costUsd: 0, hit: true };

      const pending = inFlight.get(key);
      if (pending) {
        const resolved = await pending;
        return { page: resolved.page, costUsd: 0, hit: true };
      }

      const promise = (async () => {
        const disk = await readDisk(key, now());
        if (disk) {
          entries.delete(key);
          entries.set(key, disk);
          pruneMemory(now());
          return { page: disk.page, costUsd: 0, hit: true };
        }

        const { page, costUsd } = await produce();
        const storedAt = now();
        const entry: StoredEntry = { storedAt, page };
        entries.delete(key);
        entries.set(key, entry);
        pruneMemory(storedAt);
        await writeDisk(key, entry);
        return { page, costUsd, hit: false };
      })();

      inFlight.set(key, promise);
      try {
        return await promise;
      } finally {
        inFlight.delete(key);
      }
    },
  };
};
