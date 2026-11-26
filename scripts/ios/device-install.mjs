import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";

const usage = "Usage: npm run device-install -- --device UDID [--configuration Release|Debug] [--dry-run]";
const outputsByConfiguration = {
  Release: "amplify_outputs.prod.json",
  Debug: "amplify_outputs.dev.json",
};

function checkAuthOutputs(appDir, configuration) {
  const file = outputsByConfiguration[configuration];
  const fullPath = join(appDir, "Resources", file);
  let raw;
  try {
    raw = readFileSync(fullPath, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      return configuration === "Release"
        ? `Release requires ios/App/Resources/${file} (without it the app falls back to guest mode; prod pool waits on TKL-1037 / TKL-965). Pass --configuration Debug to install against the dev pool.`
        : `Debug requires ios/App/Resources/${file} (without it the app falls back to guest mode).`;
    }
    throw error;
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return `ios/App/Resources/${file} is not valid JSON (the app would fall back to guest mode)`;
  }
  const poolId = parsed?.auth?.user_pool_id;
  const clientId = parsed?.auth?.user_pool_client_id;
  if (typeof poolId !== "string" || !poolId.trim() || typeof clientId !== "string" || !clientId.trim()) {
    return `ios/App/Resources/${file} is missing auth.user_pool_id or auth.user_pool_client_id (the app would fall back to guest mode)`;
  }
  return null;
}

function readRecord(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
}

function saveInstall(path, device, entry) {
  const record = { ...readRecord(path), [device]: entry };
  const pending = `${path}.${randomUUID()}`;
  try {
    writeFileSync(pending, JSON.stringify(record, null, 2) + "\n");
    renameSync(pending, path);
  } finally {
    rmSync(pending, { force: true });
  }
}

function execute(command, args, cwd) {
  execFileSync(command, args, { cwd, stdio: "inherit" });
}

export function run(argv, { cwd = process.cwd(), exec = execute, log = console.log } = {}) {
  const git = (...args) => execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
  try {
    const { values } = parseArgs({
      args: argv,
      options: {
        device: { type: "string" },
        configuration: { type: "string", default: "Release" },
        "dry-run": { type: "boolean" },
        help: { type: "boolean" },
      },
    });
    if (values.help) {
      log(usage);
      return 0;
    }
    const device = values.device?.trim();
    if (!device || device.startsWith("-")) throw new Error(usage);
    const configuration = values.configuration;
    if (!Object.hasOwn(outputsByConfiguration, configuration)) {
      throw new Error("--configuration must be Release or Debug");
    }

    if (git("status", "--porcelain", "--untracked-files=all")) {
      log("device-install: refused: the working tree has uncommitted changes");
      return 2;
    }
    git("fetch", "--quiet", "origin");
    const sha = git("rev-parse", "HEAD");
    const branch = git("rev-parse", "--abbrev-ref", "HEAD");
    try {
      git("merge-base", "--is-ancestor", sha, "origin/main");
    } catch (error) {
      if (error.status !== 1) throw error;
      log(`device-install: refused: ${sha.slice(0, 8)} is not on origin/main`);
      return 2;
    }

    const appDir = join(git("rev-parse", "--show-toplevel"), "ios/App");
    const outputsProblem = checkAuthOutputs(appDir, configuration);
    if (outputsProblem) {
      log(`device-install: refused: ${outputsProblem}`);
      return 2;
    }
    log(`device-install: ${sha.slice(0, 8)} (${branch}) · build ConfessionalChristianity in ${configuration} for generic/platform=iOS · install on ${device}`);
    if (values["dry-run"]) return 0;

    const path = join(git("rev-parse", "--path-format=absolute", "--git-common-dir"), "device-install.json");
    readRecord(path);
    const derived = mkdtempSync(join(tmpdir(), "cc-device-build-"));
    try {
      exec("xcodebuild", [
        "-project", "ConfessionalChristianity.xcodeproj", "-scheme", "ConfessionalChristianity",
        "-configuration", configuration, "-destination", "generic/platform=iOS",
        "-derivedDataPath", derived, "-allowProvisioningUpdates", "build",
      ], appDir);
      const app = join(derived, "Build", "Products", `${configuration}-iphoneos`, "ConfessionalChristianity.app");
      exec("xcrun", ["devicectl", "device", "install", "app", "--device", device, app], appDir);
      saveInstall(path, device, { sha, branch, configuration, installedAt: new Date().toISOString(), onMain: true });
    } finally {
      rmSync(derived, { recursive: true, force: true });
    }
    log(`device-install: installed ${sha.slice(0, 8)} and recorded it in ${path}`);
    return 0;
  } catch (error) {
    log(`device-install: ${error.message}`);
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = run(process.argv.slice(2));
}
