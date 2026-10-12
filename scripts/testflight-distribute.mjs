// After an upload: wait until App Store Connect has processed the build, set
// the "What to Test" notes, and, when a group is named, add the build to that
// external TestFlight group (the public link) and submit it for Beta App
// Review. Internal groups with automatic distribution get the build without
// this step.
//
// Auth is an App Store Connect API key (.p8, ES256). No third-party packages.
//
// Called by scripts/release-ios-beta.sh, which exports ASC_KEY_ID,
// ASC_ISSUER_ID and ASC_KEY_PATH from the release machine's release.env:
//
//   node scripts/testflight-distribute.mjs --bundle-id ID --version X.Y.Z
//     --build-number N [--notes TEXT] [--group NAME]

import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";

const API = "https://api.appstoreconnect.apple.com/v1";

function token({ keyId, issuerId, keyPath }) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })).toString("base64url");
  const claims = Buffer.from(JSON.stringify({ iss: issuerId, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" })).toString("base64url");
  const signer = createSign("SHA256");
  signer.update(`${header}.${claims}`);
  const signature = signer.sign({ key: readFileSync(keyPath, "utf8"), dsaEncoding: "ieee-p1363" }).toString("base64url");
  return `${header}.${claims}.${signature}`;
}

async function call(auth, method, path, json) {
  const response = await fetch(path.startsWith("http") ? path : `${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token(auth)}`, ...(json ? { "Content-Type": "application/json" } : {}) },
    body: json ? JSON.stringify(json) : undefined,
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const detail = body.errors?.map((error) => error.detail || error.title).join("; ") || text.slice(0, 300);
    const error = new Error(`${method} ${path} failed (${response.status}): ${detail}`);
    error.status = response.status;
    throw error;
  }
  return body;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * @param {object} options
 * @param {{keyId: string, issuerId: string, keyPath: string}} options.auth
 * @param {string} options.bundleId        e.g. "eu.brevmail.brev.ios".
 * @param {string} options.version         Marketing version, e.g. "0.2.8".
 * @param {string} options.buildNumber     CFBundleVersion of the uploaded build.
 * @param {string} [options.groupName]     External TestFlight group to add the build to.
 * @param {string} [options.whatToTest]    Notes shown to testers (en-US).
 * @param {number} [options.timeoutMinutes]
 */
async function finishTestFlightBuild({ auth, bundleId, version, buildNumber, groupName, whatToTest, timeoutMinutes = 45 }) {
  const apps = await call(auth, "GET", `/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`);
  const app = apps.data?.[0];
  if (!app) throw new Error(`No App Store Connect app with bundle id ${bundleId}`);

  // Processing usually takes 5–20 minutes after the upload finishes.
  const deadline = Date.now() + timeoutMinutes * 60_000;
  let build;
  while (Date.now() < deadline) {
    const builds = await call(
      auth,
      "GET",
      `/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(buildNumber)}&filter[preReleaseVersion.version]=${encodeURIComponent(version)}&limit=1`,
    );
    build = builds.data?.[0];
    const state = build?.attributes?.processingState;
    if (state === "VALID") break;
    if (state === "FAILED" || state === "INVALID") throw new Error(`Build ${version} (${buildNumber}) processing ${state}`);
    console.log(`TestFlight: waiting for build ${version} (${buildNumber}) to finish processing${state ? ` (${state})` : ""}…`);
    await sleep(30_000);
  }
  if (build?.attributes?.processingState !== "VALID") {
    throw new Error(`Build ${version} (${buildNumber}) was not processed within ${timeoutMinutes} minutes`);
  }

  if (whatToTest?.trim()) {
    const localizations = await call(auth, "GET", `/builds/${build.id}/betaBuildLocalizations`);
    const existing = localizations.data?.find((item) => item.attributes?.locale === "en-US");
    if (existing) {
      await call(auth, "PATCH", `/betaBuildLocalizations/${existing.id}`, {
        data: { type: "betaBuildLocalizations", id: existing.id, attributes: { whatsNew: whatToTest } },
      });
    } else {
      await call(auth, "POST", "/betaBuildLocalizations", {
        data: {
          type: "betaBuildLocalizations",
          attributes: { locale: "en-US", whatsNew: whatToTest },
          relationships: { build: { data: { type: "builds", id: build.id } } },
        },
      });
    }
  }

  if (!groupName) return { buildId: build.id };

  const groups = await call(auth, "GET", `/apps/${app.id}/betaGroups?limit=200`);
  const group = groups.data?.find((item) => item.attributes?.name === groupName);
  if (!group) throw new Error(`No TestFlight group named "${groupName}"`);

  await call(auth, "POST", `/betaGroups/${group.id}/relationships/builds`, {
    data: [{ type: "builds", id: build.id }],
  });

  if (!group.attributes?.isInternalGroup) {
    try {
      await call(auth, "POST", "/betaAppReviewSubmissions", {
        data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } },
      });
      console.log("TestFlight: submitted for Beta App Review (later builds of an approved version usually pass quickly).");
    } catch (error) {
      // 409: already submitted or no review needed for this build.
      if (error.status !== 409) throw error;
    }
  }
  return { buildId: build.id, groupId: group.id };
}

const { values: args } = parseArgs({
  options: {
    "bundle-id": { type: "string" },
    version: { type: "string" },
    "build-number": { type: "string" },
    notes: { type: "string" },
    group: { type: "string" },
  },
});
for (const name of ["bundle-id", "version", "build-number"]) {
  if (!args[name]) {
    console.error(`testflight-distribute: --${name} is required`);
    process.exit(2);
  }
}
for (const name of ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"]) {
  if (!process.env[name]) {
    console.error(`testflight-distribute: ${name} is not set`);
    process.exit(2);
  }
}

try {
  await finishTestFlightBuild({
    auth: { keyId: process.env.ASC_KEY_ID, issuerId: process.env.ASC_ISSUER_ID, keyPath: process.env.ASC_KEY_PATH },
    bundleId: args["bundle-id"],
    version: args.version,
    buildNumber: args["build-number"],
    whatToTest: args.notes,
    groupName: args.group,
  });
  console.log(args.group ? `TestFlight: notes set and build added to "${args.group}".` : "TestFlight: notes set.");
} catch (error) {
  console.error(`testflight-distribute: ${error.message}`);
  process.exit(1);
}
