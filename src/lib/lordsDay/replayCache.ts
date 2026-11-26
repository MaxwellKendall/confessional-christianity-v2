import { createHash } from 'crypto';

import type { DraftCard } from './cards';
import type { PageInput } from './gemini';

// Per-account in-memory replay cache for generated Lord's Day pages (TKL-940).
// Once a page has been generated, a retry returns that exact same page — cards
// and stable sourceKeys included — instead of calling Gemini again, so new
// wording or reordered output can't duplicate cards the person already reviewed.
// Keyed only by a SHA-256 digest of (account sub, model, page input, metadata):
// no photo bytes are retained in memory, and failed pages are never cached.

export type CachedPageCard = Omit<DraftCard, 'id' | 'page'> & { sourceKey: string };

export interface CachedPage {
  extractedText: string;
  rejected: number;
  cards: CachedPageCard[];
}

export interface PageReplayCache {
  getOrCreate: (
    key: string,
    produce: () => Promise<{ page: CachedPage; costUsd: number }>,
  ) => Promise<{ page: CachedPage; costUsd: number; hit: boolean }>;
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

export const createPageReplayCache = ({
  ttlMs = 24 * 60 * 60 * 1000,
  maxEntries = 500,
  now = Date.now,
}: {
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
} = {}): PageReplayCache => {
  const entries = new Map<string, { storedAt: number; page: CachedPage }>();
  const inFlight = new Map<string, Promise<CachedPage>>();

  const prune = (t: number) => {
    for (const [k, entry] of entries) {
      if (t - entry.storedAt >= ttlMs) entries.delete(k);
    }
    while (entries.size > maxEntries) {
      const oldest = entries.keys().next().value;
      if (oldest === undefined) break;
      entries.delete(oldest);
    }
  };

  return {
    async getOrCreate(key, produce) {
      const t = now();
      const existing = entries.get(key);
      if (existing) {
        if (t - existing.storedAt < ttlMs) {
          entries.delete(key);
          entries.set(key, existing);
          return { page: existing.page, costUsd: 0, hit: true };
        }
        entries.delete(key);
      }

      const pending = inFlight.get(key);
      if (pending) {
        const page = await pending;
        return { page, costUsd: 0, hit: true };
      }

      let producedCost = 0;
      const promise = produce().then(({ page, costUsd }) => {
        producedCost = costUsd;
        const storedAt = now();
        entries.delete(key);
        entries.set(key, { storedAt, page });
        prune(storedAt);
        return page;
      });
      inFlight.set(key, promise);
      try {
        const page = await promise;
        return { page, costUsd: producedCost, hit: false };
      } finally {
        inFlight.delete(key);
      }
    },
  };
};
