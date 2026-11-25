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

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "cc-device-install-"));
  calls = [];
  log = vi.fn();
  git("init", "-q", "-b", "main");
  git("config", "user.name", "Install Test");
  git("config", "user.email", "install@example.invalid");
  git("config", "commit.gpgsign", "false");
  mkdirSync(join(root, "ios/App/ConfessionalChristianity.xcodeproj"), { recursive: true });
  writeFileSync(join(root, "ios/App/project.yml"), "name: ConfessionalChristianity\n");
  writeFileSync(join(root, "ios/App/ConfessionalChristianity.xcodeproj/project.pbxproj"), "committed\n");
  git("add", ".");
  git("commit", "-qm", "main");
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

test("regenerates the project, then builds the Release app and records each successful device install", { timeout: 30_000 }, () => {
  expect(install("--device", "PHONE")).toBe(0);
  const appDir = join(git("rev-parse", "--show-toplevel"), "ios/App");
  expect(calls.map(([command]) => command)).toEqual(["xcodegen", "xcodebuild", "xcrun"]);
  expect(calls[0]).toEqual(["xcodegen", ["generate"], appDir]);
  expect(calls[1]).toEqual(["xcodebuild", expect.arrayContaining([
    "-scheme", "ConfessionalChristianity", "-configuration", "Release",
    "-destination", "generic/platform=iOS",
  ]), appDir]);
  expect(calls[2]).toEqual(["xcrun", [
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

test("a regeneration that changes the project is reported and leaves the tree as it found it", { timeout: 30_000 }, () => {
  const project = join(root, "ios/App/ConfessionalChristianity.xcodeproj");
  expect(run(["--device", "PHONE"], {
    cwd: join(root, "ios/App"),
    log,
    exec: (command, argv, cwd) => {
      calls.push([command, argv, cwd]);
      if (command === "xcodegen") {
        writeFileSync(join(project, "project.pbxproj"), "regenerated\n");
        writeFileSync(join(project, "new-file"), "");
      }
    },
  })).toBe(0);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/WARNING.*project\.pbxproj.*xcodegen generate.*commit/s));
  expect(git("status", "--porcelain", "--untracked-files=all")).toBe("");
  expect(readFileSync(join(project, "project.pbxproj"), "utf8")).toBe("committed\n");
});

test("restores the tree even when the build fails after regenerating", { timeout: 30_000 }, () => {
  const project = join(root, "ios/App/ConfessionalChristianity.xcodeproj");
  expect(run(["--device", "PHONE"], {
    cwd: root,
    log,
    exec: (command) => {
      if (command === "xcodegen") writeFileSync(join(project, "project.pbxproj"), "regenerated\n");
      if (command === "xcodebuild") throw new Error("build failed");
    },
  })).toBe(1);
  expect(git("status", "--porcelain", "--untracked-files=all")).toBe("");
  expect(record).toThrow(/ENOENT/);
});

test("--configuration Debug builds, installs and records the Debug app", { timeout: 30_000 }, () => {
  expect(install("--device", "PHONE", "--configuration", "Debug")).toBe(0);
  expect(calls[1][1]).toEqual(expect.arrayContaining(["-configuration", "Debug"]));
  expect(calls[2][1].at(-1)).toMatch(/Debug-iphoneos\/ConfessionalChristianity\.app$/);
  expect(record().PHONE.configuration).toBe("Debug");
});

test("rejects an unknown configuration before building", () => {
  expect(install("--device", "PHONE", "--configuration", "Profile")).toBe(1);
  expect(log).toHaveBeenCalledWith(expect.stringMatching(/Release or Debug/));
  expect(calls).toEqual([]);
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
