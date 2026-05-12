#!/usr/bin/env node

import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  isAccessibilityDenied,
  runAccessibilityPreflight,
  staticAccessibilityHelp,
} from "./visual-snapshot/accessibility.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const artifactDir = process.env.SMOKE_ARTIFACT_DIR
  ? path.resolve(process.env.SMOKE_ARTIFACT_DIR)
  : null;
const accessibilityHelp = staticAccessibilityHelp();
const tmpRoot = await fsTempDir("playwright-dashboard-actions-smoke-");
const daemonRoot = path.join(tmpRoot, "daemon");
const readinessRoot = path.join(tmpRoot, "readiness");
const workspaceDir = path.join(tmpRoot, "workspace");
const persistentStoreDir = path.join(tmpRoot, "store");
const cliEnv = {
  ...process.env,
  PLAYWRIGHT_DAEMON_SESSION_DIR: daemonRoot,
  PWTEST_CLI_GLOBAL_CONFIG: path.join(tmpRoot, "no-global-config"),
};
const smokeId = String(process.pid);
const specs = ["alpha", "bravo"].map((slug, index) => ({
  slug,
  index,
  sessionId: `cli-act-${slug[0]}-${smokeId}`,
  label: `Actions ${titleCase(slug)}`,
  workspaceHash: null,
  workspaceDir,
  debugPort: 0,
  sessionFile: null,
  server: null,
}));

let appOpened = false;
let launchIndex = 0;
let currentReadinessDir = null;
const progress = [];

await runGuiPreflight();
logProgress("Accessibility preflight passed");

try {
  logProgress("Cleaning up existing app process");
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);
  await mkdir(path.join(workspaceDir, ".playwright"), { recursive: true });

  logProgress("Checking playwright-cli availability");
  await ensurePlaywrightCLI();

  logProgress("Opening real Playwright CLI sessions");
  for (const spec of specs) {
    logProgress(`Opening ${spec.label}`);
    spec.server = await startSessionServer(spec);
    await openPlaywrightSession(spec, spec.server.rootURL);
    await loadRealSessionFile(spec);
    logProgress(`${spec.label} ready as ${spec.sessionId} on CDP ${spec.debugPort}`);
  }

  logProgress("Disabling persisted control mode default");
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  // Phase A: rename
  const renameTarget = specs[0];
  const newName = "Renamed Alpha";
  logProgress(`Phase A: renaming ${renameTarget.label} to "${newName}"`);
  await launchApp({
    extraArgs: [
      "--smoke-rename-session-id",
      renameTarget.sessionId,
      "--smoke-rename-to",
      newName,
    ],
  });
  await waitForDashboardReadiness(
    (payload) =>
      payload.safeMode === true
      && payload.activeFilter === "allOpen"
      && payload.sessions?.some(
        (session) => session.sessionId === renameTarget.sessionId && session.displayName === newName,
      ),
    `dashboard reflects rename of ${renameTarget.sessionId} to "${newName}"`,
  );
  await quitApp();
  logProgress("Phase A passed: rename surfaced in readiness payload");

  // Phase B: mark-closed + closed-history filter
  const closedTarget = specs[1];
  logProgress(`Phase B: marking ${closedTarget.label} closed and selecting closed filter`);
  await launchApp({
    extraArgs: [
      "--smoke-mark-session-closed-id",
      closedTarget.sessionId,
      "--smoke-dashboard-filter-closed",
    ],
  });
  await waitForDashboardReadiness(
    (payload) =>
      payload.safeMode === true
      && payload.activeFilter === "closed"
      && payload.sessions?.some(
        (session) => session.sessionId === closedTarget.sessionId && session.status === "closed",
      ),
    `dashboard reflects closed filter + ${closedTarget.sessionId} closed`,
  );
  await quitApp();
  logProgress("Phase B passed: closed filter + closed session surfaced in readiness payload");

  // Phase C: reorder + persistence-across-relaunch
  await mkdir(persistentStoreDir, { recursive: true });
  const [first, second] = specs;
  logProgress(
    `Phase C1: reordering ${first.label} <-> ${second.label} against persistent store`,
  );
  await launchApp({
    persistentStorePath: persistentStoreDir,
    extraArgs: [
      "--smoke-reorder-source-id",
      first.sessionId,
      "--smoke-reorder-target-id",
      second.sessionId,
    ],
  });
  await waitForDashboardReadiness(
    (payload) => {
      const ids = (payload.sessions ?? []).map((session) => session.sessionId);
      return (
        payload.safeMode === true
        && ids.length >= 2
        && ids[0] === second.sessionId
        && ids[1] === first.sessionId
      );
    },
    `dashboard reflects reorder (${second.sessionId} before ${first.sessionId})`,
  );
  await quitApp();
  logProgress("Phase C1 passed: reorder applied and reflected in readiness payload");

  logProgress("Phase C2: relaunching against same persistent store to verify persistence");
  await launchApp({
    persistentStorePath: persistentStoreDir,
  });
  await waitForDashboardReadiness(
    (payload) => {
      const ids = (payload.sessions ?? []).map((session) => session.sessionId);
      return (
        payload.safeMode === true
        && ids.length >= 2
        && ids[0] === second.sessionId
        && ids[1] === first.sessionId
      );
    },
    `reorder persists across relaunch (${second.sessionId} before ${first.sessionId})`,
  );
  await quitApp();
  logProgress("Phase C2 passed: reorder persisted across relaunch");

  logProgress("Playwright CLI dashboard-actions smoke assertions passed");
  console.log("Playwright CLI dashboard-actions smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  for (const spec of specs) {
    await closePlaywrightSession(spec);
    spec.server?.close();
  }
  await rm(tmpRoot, { recursive: true, force: true });
}

async function launchApp({ extraArgs = [], persistentStorePath = null } = {}) {
  currentReadinessDir = path.join(readinessRoot, `launch-${++launchIndex}`);
  await rm(currentReadinessDir, { recursive: true, force: true });
  await mkdir(currentReadinessDir, { recursive: true });
  const baseArgs = [
    "-n",
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-safe-mode",
    "--smoke-readiness-dir",
    currentReadinessDir,
  ];
  if (persistentStorePath) {
    baseArgs.push("--smoke-persistent-store-path", persistentStorePath);
  } else {
    baseArgs.push("--smoke-in-memory-store");
  }
  await run("open", [...baseArgs, ...extraArgs]);
  appOpened = true;
}

async function quitApp() {
  if (!appOpened) return;
  await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(
    (error) => console.warn(`Warning: failed to quit PlaywrightDashboard: ${error.message}`),
  );
  appOpened = false;
  currentReadinessDir = null;
  await sleep(1_000);
}

async function waitForDashboardReadiness(predicate, label) {
  if (!currentReadinessDir) {
    throw new Error(`No readiness directory for ${label}`);
  }
  const filePath = path.join(currentReadinessDir, "dashboard-ready.json");
  const deadline = Date.now() + 90_000;
  let lastSeen = null;
  while (Date.now() < deadline) {
    const payload = await readJSONFile(filePath).catch(() => null);
    if (payload) {
      lastSeen = payload;
      if (predicate(payload)) return payload;
    }
    await sleep(500);
  }
  const seen = lastSeen ? `\nLast payload:\n${JSON.stringify(lastSeen, null, 2)}` : "";
  throw new Error(`Timed out waiting for ${label}${seen}`);
}

async function readJSONFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function ensurePlaywrightCLI() {
  await runPlaywrightCLI(["--version"], { cwd: workspaceDir });
}

async function openPlaywrightSession(spec, url) {
  await runPlaywrightCLI(
    [`-s=${spec.sessionId}`, "open", url, "--browser=chrome", "--headed"],
    { cwd: workspaceDir, timeout: 120_000 },
  );
}

async function closePlaywrightSession(spec) {
  await runPlaywrightCLI([`-s=${spec.sessionId}`, "close"], {
    cwd: workspaceDir,
    timeout: 10_000,
  }).catch((error) => {
    return run("pkill", ["-f", `cli-daemon/program.js ${spec.sessionId}`]).catch(() => {
      console.warn(`Warning: failed to close ${spec.sessionId}: ${error.message}`);
    });
  });
}

async function loadRealSessionFile(spec) {
  const sessionFile = await findSessionFile(daemonRoot, `${spec.sessionId}.session`);
  if (!sessionFile) {
    throw new Error(`playwright-cli did not create ${spec.sessionId}.session under ${daemonRoot}`);
  }
  const config = JSON.parse(await readFile(sessionFile, "utf8"));
  const cdpPort = config.browser?.launchOptions?.cdpPort;
  if (!Number.isInteger(cdpPort) || cdpPort <= 0) {
    throw new Error(`${spec.sessionId}.session does not contain a usable CDP port`);
  }
  spec.debugPort = cdpPort;
  spec.sessionFile = sessionFile;
  spec.workspaceHash = path.basename(path.dirname(sessionFile));
}

async function findSessionFile(root, filename) {
  const entries = await readdir(root, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    const entryPath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === filename) return entryPath;
    if (entry.isDirectory()) {
      const result = await findSessionFile(entryPath, filename);
      if (result) return result;
    }
  }
  return null;
}

function startSessionServer(spec) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((_request, response) => {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(
        `<!doctype html><html><head><title>${spec.label}</title></head><body><h1>${spec.label}</h1></body></html>`,
      );
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      resolve({
        port,
        rootURL: `http://127.0.0.1:${port}/`,
        close: () => server.close(),
      });
    });
  });
}

async function runGuiPreflight() {
  try {
    await runAccessibilityPreflight();
  } catch (error) {
    if (isAccessibilityDenied(error)) {
      console.error(accessibilityHelp);
    }
    throw error;
  }
}

async function writeSmokeArtifacts(error) {
  if (!artifactDir) return;
  try {
    await mkdir(artifactDir, { recursive: true });
    await writeFile(
      path.join(artifactDir, "progress.json"),
      JSON.stringify({ progress, error: String(error?.stack ?? error) }, null, 2),
    );
    if (currentReadinessDir) {
      const target = path.join(artifactDir, "last-readiness");
      await rm(target, { recursive: true, force: true });
      await mkdir(target, { recursive: true });
      const entries = await readdir(currentReadinessDir).catch(() => []);
      for (const entry of entries) {
        const data = await readFile(path.join(currentReadinessDir, entry)).catch(() => null);
        if (data) await writeFile(path.join(target, entry), data);
      }
    }
  } catch (writeError) {
    console.error(`Warning: failed to write smoke artifacts: ${writeError.message}`);
  }
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(
      command,
      args,
      { encoding: "utf8", timeout: 60_000, ...options },
      (error, stdout, stderr) => {
        if (error) {
          error.stdout = stdout;
          error.stderr = stderr;
          reject(error);
          return;
        }
        resolve({ stdout, stderr });
      },
    );
  });
}

function runPlaywrightCLI(args, options = {}) {
  return run("playwright-cli", args, { env: cliEnv, ...options });
}

async function fsTempDir(prefix) {
  return mkdtemp(path.join(os.tmpdir(), prefix));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function logProgress(message) {
  const stamped = `[${new Date().toISOString()}] ${message}`;
  console.log(stamped);
  progress.push(stamped);
}

function titleCase(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
