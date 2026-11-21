// A fixed-window limiter keyed on the verified Cognito subject. It lives in the
// function instance's memory, so on Vercel each warm instance counts on its own:
// enough to stop one account looping on a paid API, not a global quota.

export interface RateLimiter {
  take: (key: string) => { ok: true } | { ok: false; retryAfterSeconds: number };
}

export const createRateLimiter = ({
  limit,
  windowMs,
  now = Date.now,
}: {
  limit: number;
  windowMs: number;
  now?: () => number;
}): RateLimiter => {
  const windows = new Map<string, { start: number; count: number }>();
  return {
    take(key) {
      const t = now();
      if (windows.size > 10_000) {
        for (const [k, w] of windows) if (t - w.start >= windowMs) windows.delete(k);
      }
      const current = windows.get(key);
      if (!current || t - current.start >= windowMs) {
        windows.set(key, { start: t, count: 1 });
        return { ok: true };
      }
      if (current.count >= limit) {
        return { ok: false, retryAfterSeconds: Math.max(1, Math.ceil((current.start + windowMs - t) / 1000)) };
      }
      current.count += 1;
      return { ok: true };
    },
  };
};
