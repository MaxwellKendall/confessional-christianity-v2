import { studioAuthConfigFromEnv, verifyStudioAccessToken } from '@/lib/lordsDay/auth';
import { cardsModel } from '@/lib/lordsDay/gemini';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';
import { handleRedraftRequest } from '@/lib/lordsDay/redraft';

// One card, drafted again from text already transcribed. Contract: src/lib/lordsDay/redraft.ts.
export const dynamic = 'force-dynamic';
export const maxDuration = 60;

// The same budget as drafting: a card tapped over and over cannot run up a bill.
const limiter = createRateLimiter({ limit: 20, windowMs: 60 * 60 * 1000 });

export async function POST(request: Request) {
  const studioAuth = studioAuthConfigFromEnv();
  return handleRedraftRequest(request, {
    geminiApiKey: process.env.GEMINI_API_KEY?.trim() || undefined,
    model: cardsModel(),
    verifyAccessToken: studioAuth
      ? async (token) => {
          const { sub } = await verifyStudioAccessToken(token, studioAuth);
          return { sub };
        }
      : null,
    limiter,
  });
}
