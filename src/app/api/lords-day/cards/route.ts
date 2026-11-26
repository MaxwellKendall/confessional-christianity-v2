import { tmpdir } from 'os';
import { join } from 'path';

import { studioAuthConfigFromEnv, verifyStudioAccessToken } from '@/lib/lordsDay/auth';
import { cardsModel } from '@/lib/lordsDay/gemini';
import { handleCardsRequest } from '@/lib/lordsDay/handler';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';
import { createPageReplayCache, DEFAULT_REPLAY_TTL_MS } from '@/lib/lordsDay/replayCache';

// Sermon notes → drafted Lord's Day cards (TKL-861). Contract: src/lib/lordsDay/handler.ts.
// GEMINI_API_KEY lives only in this deployment's environment, read per request;
// the app never holds a model key.
export const dynamic = 'force-dynamic';
export const maxDuration = 60;

// 20 drafts per hour per account: a sermon is drafted once a week, retries included.
const limiter = createRateLimiter({ limit: 20, windowMs: 60 * 60 * 1000 });
// Retain the original page across local dev server restarts. The hosted route
// keeps its in-memory cache and reports a miss on replay-only requests.
const replayCache = createPageReplayCache({
  dir: process.env.NODE_ENV === 'development'
    ? process.env.LORDS_DAY_REPLAY_CACHE_DIR?.trim() || join(tmpdir(), 'confessional-lords-day-replay')
    : undefined,
  ttlMs: process.env.NODE_ENV === 'development' ? DEFAULT_REPLAY_TTL_MS : 24 * 60 * 60 * 1000,
  maxEntries: 500,
  maxDiskEntries: 5000,
});

export async function POST(request: Request) {
  const studioAuth = studioAuthConfigFromEnv();
  return handleCardsRequest(request, {
    geminiApiKey: process.env.GEMINI_API_KEY?.trim() || undefined,
    model: cardsModel(),
    verifyAccessToken: studioAuth
      ? async (token) => {
          const { sub } = await verifyStudioAccessToken(token, studioAuth);
          return { sub };
        }
      : null,
    limiter,
    replayCache,
  });
}
