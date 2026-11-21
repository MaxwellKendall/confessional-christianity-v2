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

// Signing: the export first tries the ASC API key (works once the key may use cloud-managed distribution
// certificates, or this Mac holds an Apple Distribution identity). Today the key is refused (TKL-880), so
// release.mjs falls back to the Xcode account's cloud signing when cloudSigningDenied() matches.
export function exportArgs({ archivePath, exportPath, plistPath, auth }) {
  const args = ['-exportArchive', '-archivePath', archivePath, '-exportPath', exportPath, '-exportOptionsPlist', plistPath,
    '-allowProvisioningUpdates'];
  if (auth) args.push('-authenticationKeyPath', auth.keyPath, '-authenticationKeyID', auth.keyId, '-authenticationKeyIssuerID', auth.issuerId);
  return args;
}

/** True when an -exportArchive failure is the distribution-signing refusal, not some other error. */
export function cloudSigningDenied(output) {
  return /cloud signing permission error|access to cloud-managed distribution certificates|No signing certificate "iOS Distribution" found/i.test(String(output));
}

// Always a local .ipa: the upload is a separate step, authenticated by the ASC API key (altoolArgs).
export function exportPlist() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
`;
}

const ALTOOL_ACTIONS = { validate: '--validate-app', upload: '--upload-app' };

/** `xcrun` arguments to validate or upload an .ipa, authenticated only by the ASC API key. */
export function altoolArgs({ action, ipa, auth }) {
  const flag = ALTOOL_ACTIONS[action];
  if (!flag) throw new Error(`altool action must be validate or upload, got "${action}"`);
  if (!auth?.keyId || !auth?.issuerId || !auth?.keyPath) throw new Error('altool needs the ASC API key (keyId, issuerId, keyPath)');
  return ['altool', flag, '-f', ipa, '-t', 'ios', '--api-key', auth.keyId, '--api-issuer', auth.issuerId,
    '--p8-file-path', auth.keyPath, '--output-format', 'json'];
}

/** altool has exited 0 while reporting errors, so check the output as well as the exit code. */
export function altoolFailed(code, output) {
  if (code !== 0) return true;
  const text = String(output);
  return /"product-errors"\s*:\s*\[\s*\{/.test(text) || /\*\*\* Error:|^\s*ERROR:/m.test(text);
}

export function redact(text, secrets) {
  let out = String(text);
  for (const secret of secrets) if (secret && secret.length >= 4) out = out.split(secret).join('••••');
  return out;
}
