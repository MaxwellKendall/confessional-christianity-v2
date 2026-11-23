import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { run } from "./device-install.mjs";

let root, calls, log;
const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
const install = (...args) => run(args, {
  cwd: root,
  log,
  exec: (command, argv, cwd) => calls.push([command, argv, cwd]),
});
const record = () => JSON.parse(readFileSync(join(root, ".git", "device-install.json"), "utf8"));

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "cc-device-install-"));
  calls = [];
  log = vi.fn();
  git("init", "-q", "-b", "main");
  git("config", "user.name", "Install Test");
  git("config", "user.email", "install@example.invalid");
  git("config", "commit.gpgsign", "false");
  git("commit", "-qm", "main", "--allow-empty");
  git("remote", "add", "origin", ".");
});

afterEach(() => rmSync(root, { recursive: true, force: true }));

test("dry run prints a Release plan without building or recording", () => {
  expect(install("--dry-run", "--device", "PHONE")).toBe(0);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/Release.*PHONE/));
  expect(calls).toEqual([]);
  expect(record).toThrow(/ENOENT/);
});

test("refuses an unlanded commit even from a clean tree", () => {
  git("checkout", "-qb", "feature");
  git("commit", "-qm", "feature", "--allow-empty");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/not on origin\/main/));
  expect(calls).toEqual([]);
});

test("refuses a dirty landed checkout", () => {
  writeFileSync(join(root, "untracked"), "");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/uncommitted/));
  expect(calls).toEqual([]);
});

test("builds the Release app and records each successful device install", { timeout: 30_000 }, () => {
  expect(install("--device", "PHONE")).toBe(0);
  const appDir = join(git("rev-parse", "--show-toplevel"), "ios/App");
  expect(calls[0]).toEqual(["xcodebuild", expect.arrayContaining([
    "-scheme", "ConfessionalChristianity", "-configuration", "Release",
    "-destination", "generic/platform=iOS",
  ]), appDir]);
  expect(calls[1]).toEqual(["xcrun", [
    "devicectl", "device", "install", "app", "--device", "PHONE",
    expect.stringMatching(/Release-iphoneos\/ConfessionalChristianity\.app$/),
  ], appDir]);
  expect(install("--device", "SECOND")).toBe(0);
  const entry = {
    sha: git("rev-parse", "HEAD"), branch: "main", configuration: "Release",
    installedAt: expect.stringMatching(/^\d{4}-\d{2}-\d{2}T/), onMain: true,
  };
  expect(record()).toEqual({ PHONE: entry, SECOND: entry });
});

test("a failed install leaves the record alone and can be retried", { timeout: 30_000 }, () => {
  expect(run(["--device", "PHONE"], {
    cwd: root,
    log,
    exec: (command) => {
      if (command === "xcrun") throw new Error("phone unreachable");
    },
  })).toBe(1);
  expect(record).toThrow(/ENOENT/);
  expect(install("--device", "PHONE")).toBe(0);
});
