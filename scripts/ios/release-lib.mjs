// TKL-814: pure pieces of scripts/ios/release.mjs. No network, no secrets, no side effects.

export const APP_ID = '6797692942';
export const TEAM_ID = '7GZKY29XJH';
export const SCHEME = 'ConfessionalChristianity';

const USAGE = 'Usage: npm run ios:release -- [--dry-run] [--marketing-version X.Y[.Z]]';

export function parseArgs(argv) {
  const out = { dryRun: false, marketingVersion: undefined, help: false };
  const args = argv.filter((a) => a !== '--');
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--dry-run') out.dryRun = true;
    else if (arg === '--help' || arg === '-h') out.help = true;
    else if (arg === '--marketing-version' || arg.startsWith('--marketing-version=')) {
      const value = arg.includes('=') ? arg.slice(arg.indexOf('=') + 1) : args[++i];
      if (!value || !/^\d+\.\d+(\.\d+)?$/.test(value)) {
        throw new Error(`--marketing-version needs a marketing version like 1.2 or 1.2.1, got "${value ?? ''}"`);
      }
      out.marketingVersion = value;
    } else throw new Error(`Unknown argument "${arg}". ${USAGE}`);
  }
  return out;
}

export const usage = () => USAGE;

const MARKETING = /^(\s+MARKETING_VERSION: )"([^"]+)"[ \t]*$/gm;
const BUILD = /^(\s+CURRENT_PROJECT_VERSION: )"(\d+)"[ \t]*$/gm;

function single(yaml, pattern, name) {
  const values = [...yaml.matchAll(pattern)].map((m) => m[2]);
  if (!values.length) throw new Error(`${name} is missing from project.yml`);
  if (new Set(values).size > 1) throw new Error(`${name} values disagree across targets in project.yml: ${values.join(', ')}`);
  return values[0];
}

/** The app and widget share one marketing version and build number; they must agree. */
export function readVersions(yaml) {
  return { marketing: single(yaml, MARKETING, 'MARKETING_VERSION'), build: single(yaml, BUILD, 'CURRENT_PROJECT_VERSION') };
}

/** Rewrite CURRENT_PROJECT_VERSION (and MARKETING_VERSION when given) on every target. */
export function setVersions(yaml, { build, marketing }) {
  readVersions(yaml);
  let out = yaml.replace(BUILD, `$1"${build}"`);
  if (marketing) out = out.replace(MARKETING, `$1"${marketing}"`);
  return out;
}

/** Highest build number App Store Connect has ever seen for the app (expired builds still count). */
export function highestBuildNumber(builds) {
  return builds.reduce((max, b) => {
    const n = Number(b?.attributes?.version);
    return Number.isFinite(n) && n > max ? n : max;
  }, 0);
}

export function processingVerdict(build) {
  const state = build?.attributes?.processingState;
  if (state === 'VALID') return 'valid';
  if (state === 'FAILED' || state === 'INVALID') return 'failed';
  return 'waiting';
}

export function archiveArgs({ archivePath, overrides }) {
  const args = ['archive', '-scheme', SCHEME, '-configuration', 'Release', '-destination', 'generic/platform=iOS',
    '-archivePath', archivePath, '-allowProvisioningUpdates'];
  if (overrides?.build !== undefined) args.push(`CURRENT_PROJECT_VERSION=${overrides.build}`);
  if (overrides?.marketing) args.push(`MARKETING_VERSION=${overrides.marketing}`);
  return args;
}

// Signing is cloud-managed through the Xcode account on this Mac (TKL-880). Passing the ASC
// API key here fails with "not given access to cloud-managed distribution certificates".
export function exportArgs({ archivePath, exportPath, plistPath }) {
  return ['-exportArchive', '-archivePath', archivePath, '-exportPath', exportPath, '-exportOptionsPlist', plistPath,
    '-allowProvisioningUpdates'];
}

export function exportPlist({ upload }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${upload ? 'upload' : 'export'}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
`;
}

export function redact(text, secrets) {
  let out = String(text);
  for (const secret of secrets) if (secret && secret.length >= 4) out = out.split(secret).join('••••');
  return out;
}
