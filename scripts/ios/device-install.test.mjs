import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
const validOutputs = JSON.stringify({
  version: "1.4",
  auth: {
    aws_region: "us-east-1",
    user_pool_id: "us-east-1_TestPool",
    user_pool_client_id: "testclientid",
  },
});

function commitOutputs(stage, content = validOutputs) {
  const dir = join(root, "ios/App/Resources");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `amplify_outputs.${stage}.json`), content);
  git("add", ".");
  git("commit", "-qm", `add ${stage} outputs`);
}

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

test("refuses a Release install and dry run when amplify_outputs.prod.json is missing", () => {
  commitOutputs("dev");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/refused.*amplify_outputs\.prod\.json.*TKL-1037/i));
  expect(calls).toEqual([]);
  expect(record).toThrow(/ENOENT/);

  log.mockClear();
  expect(install("--dry-run", "--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/refused.*amplify_outputs\.prod\.json/i));
  expect(calls).toEqual([]);
});

test("refuses when the configuration's amplify_outputs file is invalid or incomplete", () => {
  commitOutputs("prod", "{not json");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/refused.*amplify_outputs\.prod\.json/i));
  expect(calls).toEqual([]);

  log.mockClear();
  commitOutputs("prod", JSON.stringify({ version: "1.4", auth: {} }));
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/refused.*amplify_outputs\.prod\.json/i));
  expect(calls).toEqual([]);
});

test("dry run prints a Release plan without building or recording when prod outputs exist", () => {
  commitOutputs("prod");
  expect(install("--dry-run", "--device", "PHONE")).toBe(0);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/Release.*PHONE/));
  expect(calls).toEqual([]);
  expect(record).toThrow(/ENOENT/);
});

test("refuses an unlanded commit even from a clean tree", () => {
  commitOutputs("prod");
  git("checkout", "-qb", "feature");
  git("commit", "-qm", "feature", "--allow-empty");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/not on origin\/main/));
  expect(calls).toEqual([]);
});

test("refuses a dirty landed checkout", () => {
  commitOutputs("prod");
  writeFileSync(join(root, "untracked"), "");
  expect(install("--device", "PHONE")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/uncommitted/));
  expect(calls).toEqual([]);
});

test("builds the Release app and records each successful device install", { timeout: 30_000 }, () => {
  commitOutputs("prod");
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

test("--configuration Debug builds, installs and records the Debug app using amplify_outputs.dev.json", { timeout: 30_000 }, () => {
  commitOutputs("dev");
  expect(install("--device", "PHONE", "--configuration", "Debug")).toBe(0);
  expect(calls[0][1]).toEqual(expect.arrayContaining(["-configuration", "Debug"]));
  expect(calls[1][1].at(-1)).toMatch(/Debug-iphoneos\/ConfessionalChristianity\.app$/);
  expect(record().PHONE.configuration).toBe("Debug");
});

test("refuses --configuration Debug when amplify_outputs.dev.json is missing", () => {
  commitOutputs("prod");
  expect(install("--device", "PHONE", "--configuration", "Debug")).toBe(2);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/refused.*amplify_outputs\.dev\.json/i));
  expect(calls).toEqual([]);
});

test("rejects an unknown configuration before building", () => {
  commitOutputs("prod");
  expect(install("--device", "PHONE", "--configuration", "Profile")).toBe(1);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/Release or Debug/));
  expect(calls).toEqual([]);
});

test("a failed install leaves the record alone and can be retried", { timeout: 30_000 }, () => {
  commitOutputs("prod");
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
