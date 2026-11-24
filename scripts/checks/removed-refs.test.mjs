import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

import { ALLOWED, findUnexpectedRefs } from './removed-refs.mjs';

const repoRoot = path.resolve(import.meta.dirname, '../..');
const script = path.join(import.meta.dirname, 'removed-refs.mjs');

let dirs = [];
afterEach(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
  dirs = [];
});

function fixtureRepo(files) {
  const dir = mkdtempSync(path.join(tmpdir(), 'removed-refs-'));
  dirs.push(dir);
  const git = (...args) => execFileSync('git', args, { cwd: dir, stdio: 'pipe' });
  git('init', '-q');
  for (const [file, body] of Object.entries(files)) {
    mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
    writeFileSync(path.join(dir, file), body);
  }
  git('add', '-A');
  return dir;
}

describe('removed prayer-list reference check (TKL-886)', () => {
  it('allows the original migration, the reversal migration and the removal test', () => {
    const files = Object.fromEntries(ALLOWED.map((f) => [f, 'drop table prayer_people;\n']));
    expect(findUnexpectedRefs(fixtureRepo(files))).toEqual([]);
  });

  it('reports any other tracked reference, case-insensitively, with file and line', () => {
    const dir = fixtureRepo({
      [ALLOWED[0]]: 'create table prayer_people ();\n',
      'src/lib/people.ts': 'const a = 1;\nfrom("Prayer_People")\n',
      'ios/App/Sources/X.swift': 'let t = "PRAYER_PEOPLE"\n',
    });
    expect(findUnexpectedRefs(dir)).toEqual([
      'ios/App/Sources/X.swift:1:let t = "PRAYER_PEOPLE"',
      'src/lib/people.ts:2:from("Prayer_People")',
    ]);
  });

  it('ignores untracked files', () => {
    const dir = fixtureRepo({ 'README.md': 'nothing here\n' });
    writeFileSync(path.join(dir, 'scratch.sql'), 'select * from prayer_people;\n');
    expect(findUnexpectedRefs(dir)).toEqual([]);
  });

  it('finds no unexpected references in this repo', () => {
    expect(findUnexpectedRefs(repoRoot)).toEqual([]);
  });

  it('exits non-zero and lists the reference when run as a command', () => {
    const dir = fixtureRepo({ 'app.ts': 'prayer_people\n' });
    let status = 0;
    let out = '';
    try {
      execFileSync('node', [script], { cwd: dir, stdio: 'pipe' });
    } catch (e) {
      status = e.status;
      out = e.stdout.toString() + e.stderr.toString();
    }
    expect(status).toBe(1);
    expect(out).toContain('app.ts:1:prayer_people');
  });
});
