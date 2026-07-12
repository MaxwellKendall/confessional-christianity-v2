#!/usr/bin/env node
import {
  DEFAULT_SLUG,
  allQuestionNumbers,
  getQuestion,
  parseNumberList,
  readPrayers,
  writePrayer,
} from './prayers-lib.mjs';

const args = process.argv.slice(2);
const readArg = (name, fallback = null) => {
  const idx = args.indexOf(name);
  return idx === -1 ? fallback : args[idx + 1];
};
const hasFlag = (name) => args.includes(name);

const slug = readArg('--slug', DEFAULT_SLUG);
const questionSpec = readArg('--questions');
const model = readArg('--model', process.env.ANTHROPIC_MODEL ?? 'claude-sonnet-4-5');
const dryRun = hasFlag('--dry-run');
const force = hasFlag('--force');
const all = hasFlag('--all');
const limit = Number(readArg('--limit', 0));

if (!questionSpec && !all) {
  throw new Error('Pass --questions with a number list, or pass --all to draft every missing prayer.');
}

const existing = await readPrayers(slug);
const existingByQuestion = new Map(existing.map((p) => [p.question, p]));
const examples = existing
  .filter((p) => p.status === 'approved')
  .slice(0, 8)
  .map((p) => `Q${p.question}: ${p.body}`)
  .join('\n\n');

let questionNumbers = questionSpec
  ? parseNumberList(questionSpec)
  : await allQuestionNumbers();

questionNumbers = questionNumbers.filter((n) => force || !existingByQuestion.has(n));
if (limit > 0) questionNumbers = questionNumbers.slice(0, limit);

if (!questionNumbers.length) {
  console.log('No missing prayers to draft.');
  process.exit(0);
}

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!dryRun && !apiKey) {
  throw new Error('ANTHROPIC_API_KEY is required unless you pass --dry-run.');
}

const system = [
  'You draft short prayers for a family catechesis app rooted in historic Reformed Protestant theology.',
  'Return only the prayer text, with no title, markdown, commentary, or quotation marks.',
  'Rules: address God directly; include the literal placeholder {name}; use warm contemporary English; write two or three sentences; keep it suitable for a parent praying over a child; stay faithful to the Westminster Shorter Catechism answer and proof texts; end with Amen.',
  'Do not approve your own work. A human reviewer will edit and approve drafts before publication.',
].join(' ');

const buildPrompt = (q) => [
  examples ? `Approved style examples:\n${examples}` : null,
  `Draft one prayer for Westminster Shorter Catechism question ${q.number}.`,
  `Question: ${q.question}`,
  `Answer: ${q.answer}`,
  q.proofTexts.length ? `Proof texts: ${q.proofTexts.join('; ')}` : 'Proof texts: none listed',
].filter(Boolean).join('\n\n');

const cleanPrayer = (text) => text
  .trim()
  .replace(/^["'“”]+|["'“”]+$/g, '')
  .trim();

const draftPrayer = async (q) => {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model,
      max_tokens: 220,
      temperature: 0.45,
      system,
      messages: [{ role: 'user', content: buildPrompt(q) }],
    }),
  });

  const json = await res.json();
  if (!res.ok) {
    const message = json?.error?.message ?? JSON.stringify(json);
    throw new Error(`Anthropic API error for Q${q.number}: ${message}`);
  }

  const body = json.content
    ?.filter((part) => part.type === 'text')
    .map((part) => part.text)
    .join('\n')
    .trim();
  if (!body) throw new Error(`Anthropic returned no text for Q${q.number}.`);

  const prayer = cleanPrayer(body);
  if (!prayer.includes('{name}')) throw new Error(`Draft for Q${q.number} did not include {name}.`);
  if (!/Amen\.$/.test(prayer)) throw new Error(`Draft for Q${q.number} did not end with Amen.`);
  return prayer;
};

for (const n of questionNumbers) {
  const q = await getQuestion(n);
  if (!q) throw new Error(`Unknown WSC question ${n}.`);

  if (dryRun) {
    console.log(`[dry-run] Would draft Q${n}: ${q.question}`);
    continue;
  }

  const body = await draftPrayer(q);
  await writePrayer(slug, n, {
    body,
    status: 'draft',
    source: 'llm',
    model,
  });
  console.log(`Drafted Q${n}`);
}
