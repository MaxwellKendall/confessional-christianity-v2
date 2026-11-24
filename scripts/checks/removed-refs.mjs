#!/usr/bin/env node
// Reports tracked references to the cut prayer list's `prayer_people` table
// (TKL-869, TKL-886). A plain `rg -i prayer_people` also matches files that
// must name the table, so those are allowed by path and everything else is
// reported. Run from the repo root: `npm run check:removed-refs`.
// Exit 0 = no unexpected references, 1 = some found (listed as file:line:text).
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const TERM = 'prayer_people';

// Files that may name the table. The three Supabase files were deleted with
// the rest of the retired schema in TKL-904; they stay listed so that history
// checkouts before TKL-904 pass too.
export const ALLOWED = [
  'supabase/migrations/20261118000000_prayer_list.sql', // original migration
  'supabase/migrations/20261120000000_drop_prayer_list.sql', // reversal migration
  'supabase/tests/prayer_list_removed.test.sql', // removal test
  'scripts/checks/removed-refs.mjs', // this check
  'scripts/checks/removed-refs.test.mjs', // its test
];

export function findUnexpectedRefs(cwd = process.cwd()) {
  let out;
  try {
    // Tracked files only; -I skips binaries; --full-name keeps paths repo-relative.
    out = execFileSync('git', ['grep', '-n', '-i', '-I', '--full-name', '-F', TERM], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (e) {
    if (e.status === 1) return []; // git grep: no matches
    throw e;
  }
  return out
    .split('\n')
    .filter(Boolean)
    .filter((line) => !ALLOWED.includes(line.slice(0, line.indexOf(':'))))
    .sort();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const found = findUnexpectedRefs();
  if (found.length) {
    console.log(`Unexpected ${TERM} references (${found.length}):`);
    for (const line of found) console.log(line);
    process.exit(1);
  }
  console.log(`OK: no unexpected ${TERM} references.`);
}
