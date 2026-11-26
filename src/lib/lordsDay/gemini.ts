import { GENERATION_SCHEMA } from './cards';

// The vision call follows remix's photo-import pattern (TKL-861, decision D4):
// Gemini, model behind an env override, JSON enforced at the API, cost per call,
// typed errors, and a golden eval (evals/lords-day-cards) that picks the model.

// gemini-3.8-flash over gemini-3.5-flash-lite (eval 2026-11-21, 12 real note photos,
// evals/lords-day-cards/results): flash passed 12/12 then 11/12 across two runs
// (sermon-07 fell to 1 of 4 key spans once); flash-lite passed 8/12, missing the
// sermon passage's Verse card on 3 photos and the key spans on 1. Realized cost for
// flash: ~$0.017 per photo, thinking included, median ~14-16 s. flash-lite ran ~2 s
// and under $0.006 per photo even priced at flash's rates below, but a third of its
// sermons lose the passage or the points, so the cheaper call is a false economy.
export const GEMINI_CARDS_MODEL_DEFAULT = 'gemini-3.8-flash';
// Standard rates from 2027-01-01 (intro pricing until then is half this): errs high.
// Same model and rates as remix's GEMINI_BOX_* constants.
export const GEMINI_CARDS_INPUT_PER_1M = 1.5;
export const GEMINI_CARDS_OUTPUT_PER_1M = 7.5;

export const cardsModel = (): string => process.env.GEMINI_CARDS_MODEL?.trim() || GEMINI_CARDS_MODEL_DEFAULT;

export interface GeminiUsage {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  thoughtsTokenCount?: number;
}

/** Thinking tokens bill as output. */
export const geminiCost = (usage: GeminiUsage | undefined): number => {
  if (!usage) return 0;
  const output = (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0);
  return ((usage.promptTokenCount ?? 0) / 1_000_000) * GEMINI_CARDS_INPUT_PER_1M + (output / 1_000_000) * GEMINI_CARDS_OUTPUT_PER_1M;
};

/** An expected failure, mapped by the route to a status instead of a raw 500. */
export class CardsError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'CardsError';
  }
}

export type PageInput = { kind: 'image'; data: string; mimeType: string } | { kind: 'text'; text: string };

export interface SermonMeta {
  passage?: string;
  title?: string;
}

export interface DraftPageOptions {
  apiKey: string;
  model: string;
  fetchImpl?: typeof fetch;
  /** extra attempts on a dropped connection, 429 or 5xx (the JSON body is safe to resend) */
  retries?: number;
  retryDelayMs?: number;
  timeoutMs?: number;
}

export interface DraftPageResult {
  extractedText: string;
  rawCards: unknown[];
  usage?: GeminiUsage;
  costUsd: number;
}

const INSTRUCTIONS = `You turn one Christian's notes on a Sunday sermon into short cards they will revisit through the week.

Return JSON with:
- extractedText: a faithful transcription of the notes. Keep the writer's words and abbreviations; do not fix, expand or add anything. Mark an unreadable word as [?].
- cards: one card for each distinct point, quotable line and passage the notes actually contain, in the order the notes run. Let the notes decide how many: a sparse page may give only two or three, a full page of a well-structured sermon may give a dozen or more. Never pad with filler to reach a number, and never leave out something worth keeping to stay under one. Each card is exactly one of three kinds:
  - key_point: one main point of the sermon as one clear sentence (at most 200 characters), in plain words, faithful to the notes. Never add doctrine the notes do not contain.
  - quote: a memorable line copied character for character from extractedText. Never compose, paraphrase, merge or tidy a quote. If no line is worth quoting, give no quote cards.
  - verse: a Bible passage named in the notes, as a reference only, with the full English book name ("Psalm 86:5", "1 Thessalonians 3", "Matthew 5:43-48"). Never write the words of Scripture, and never add a passage the notes do not name.
Do not name the preacher or anyone else as the speaker of a quote.`;

const promptFor = (input: PageInput, meta: SermonMeta) => {
  const context = [
    meta.title ? `Sermon title: ${meta.title}` : '',
    meta.passage ? `Sermon passage: ${meta.passage}` : '',
  ].filter(Boolean);
  const parts = [INSTRUCTIONS, ...context];
  if (input.kind === 'text') {
    parts.push('The notes were typed, not photographed. Set extractedText to an empty string.', `Notes:\n${input.text}`);
  } else {
    parts.push('The notes are handwritten, in the photo above.');
  }
  return parts.join('\n\n');
};

const sleep = (ms: number) => (ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve());

const RETRYABLE_STATUS = new Set([429, 500, 502, 503, 504]);

export const draftPage = async (input: PageInput, meta: SermonMeta, options: DraftPageOptions): Promise<DraftPageResult> => {
  const { apiKey, model, fetchImpl = fetch, retries = 2, retryDelayMs = 500, timeoutMs = 50_000 } = options;
  const parts: Record<string, unknown>[] = [];
  if (input.kind === 'image') parts.push({ inlineData: { mimeType: input.mimeType, data: input.data } });
  parts.push({ text: promptFor(input, meta) });
  const body = JSON.stringify({
    contents: [{ role: 'user', parts }],
    generationConfig: { responseMimeType: 'application/json', responseJsonSchema: GENERATION_SCHEMA },
  });
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;

  let response: Response | undefined;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      response = await fetchImpl(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': apiKey },
        body,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      if (attempt === retries) {
        const name = error instanceof Error ? error.name : 'Error';
        throw new CardsError(502, 'provider_unreachable', `Couldn't reach the card generator (${name}). Try again.`);
      }
      await sleep(retryDelayMs * (attempt + 1));
      continue;
    }
    if (response.ok || !RETRYABLE_STATUS.has(response.status) || attempt === retries) break;
    await sleep(retryDelayMs * (attempt + 1));
  }

  if (!response || !response.ok) {
    throw new CardsError(502, 'provider_error', `The card generator returned ${response?.status ?? 'nothing'}. Try again.`);
  }

  let data: {
    candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
    usageMetadata?: GeminiUsage;
  };
  try {
    data = await response.json();
  } catch {
    throw new CardsError(502, 'bad_model_output', 'The card generator returned an unreadable reply.');
  }
  const candidate = data.candidates?.[0];
  if (candidate?.finishReason && ['SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'RECITATION'].includes(candidate.finishReason)) {
    throw new CardsError(422, 'blocked', 'The card generator declined these notes.');
  }
  const text = candidate?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new CardsError(502, 'bad_model_output', 'The card generator returned invalid JSON.');
  }
  const { extractedText, cards } = (parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}) as Record<
    string,
    unknown
  >;
  if (!Array.isArray(cards)) {
    throw new CardsError(502, 'bad_model_output', 'The card generator returned no card list.');
  }
  return {
    extractedText: input.kind === 'text' ? input.text : typeof extractedText === 'string' ? extractedText : '',
    rawCards: cards,
    usage: data.usageMetadata,
    costUsd: geminiCost(data.usageMetadata),
  };
};
