import { cognitoConfigFromEnv, verifierFor } from '@/lib/lordsDay/auth';
import { cardsModel } from '@/lib/lordsDay/gemini';
import { handleCardsRequest } from '@/lib/lordsDay/handler';
import { createRateLimiter } from '@/lib/lordsDay/rateLimit';

// Sermon notes → drafted Lord's Day cards (TKL-861). Contract: src/lib/lordsDay/handler.ts.
// GEMINI_API_KEY lives only in this deployment's environment, read per request;
// the app never holds a model key.
export const dynamic = 'force-dynamic';
export const maxDuration = 60;

// 20 drafts per hour per account: a sermon is drafted once a week, retries included.
const limiter = createRateLimiter({ limit: 20, windowMs: 60 * 60 * 1000 });

export async function POST(request: Request) {
  const cognito = cognitoConfigFromEnv();
  const verifier = cognito ? verifierFor(cognito) : null;
  return handleCardsRequest(request, {
    geminiApiKey: process.env.GEMINI_API_KEY?.trim() || undefined,
    model: cardsModel(),
    verifyAccessToken: verifier
      ? async (token) => {
          const payload = await verifier.verify(token);
          return { sub: String(payload.sub) };
        }
      : null,
    limiter,
  });
}
