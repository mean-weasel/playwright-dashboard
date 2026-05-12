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
const killSlaMs = Number.parseInt(process.env.RELIABILITY_KILL_SLA_MS ?? "30000", 10);
const restartSlaMs = Number.parseInt(process.env.RELIABILITY_RESTART_SLA_MS ?? "60000", 10);
const accessibilityHelp = staticAccessibilityHelp();
const tmpRoot = await mkdtemp(
  path.join(os.tmpdir(), "playwright-dashboard-reliability-smoke-"),
);
const daemonRoot = path.join(tmpRoot, "daemon");
const readinessRoot = path.join(tmpRoot, "readiness");
const workspaceDir = path.join(tmpRoot, "workspace");
const cliEnv = {
  ...process.env,
  PLAYWRIGHT_DAEMON_SESSION_DIR: daemonRoot,
  PWTEST_CLI_GLOBAL_CONFIG: path.join(tmpRoot, "no-global-config"),
};
const smokeId = String(process.pid);

const specs = {
  kill: {
    slug: "kill",
    sessionId: `cli-rel-kill-${smokeId}`,
    label: "Reliability Kill",
    debugPort: 0,
    sessionFile: null,
    server: null,
  },
  restart: {
    slug: "restart",
    sessionId: `cli-rel-restart-${smokeId}`,
    label: "Reliability Restart",
    debugPort: 0,
    sessionFile: null,
    server: null,
  },
};

let appOpened = false;
let currentReadinessDir = null;
let launchIndex = 0;
const progress = [];

await runGuiPreflight();
logProgress("Accessibility preflight passed");

try {
  logProgress("Cleaning up existing app process");
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);
  await mkdir(path.join(workspaceDir, ".playwright"), { recursive: true });
  await ensurePlaywrightCLI();

  for (const spec of Object.values(specs)) {
    spec.server = await startSessionServer(spec);
  }

  // Set up the kill session up front so the dashboard sees it on launch.
  logProgress(`Opening kill-target CLI session ${specs.kill.sessionId}`);
  await openPlaywrightSession(specs.kill, specs.kill.server.rootURL);
  await loadRealSessionFile(specs.kill);
  logProgress(`${specs.kill.label} ready on CDP ${specs.kill.debugPort}`);

  logProgress("Disabling persisted control mode default");
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  // The whole smoke runs against a single long-lived dashboard launch so
  // Phase 2 can verify "without restarting the app".
  logProgress("Launching dashboard for full smoke run");
  await launchApp();

  // Phase 1: Chrome kill mid-session
  logProgress("Phase 1: waiting for dashboard to discover kill-target session");
  await waitForDashboardReadiness(
    (payload) =>
      payload.safeMode === true
      && payload.sessions?.some(
        (session) =>
          session.sessionId === specs.kill.sessionId && session.status !== "closed",
      ),
    `dashboard discovers ${specs.kill.sessionId} as active`,
    60_000,
  );
  logProgress(`Killing Chrome for ${specs.kill.sessionId} (debug port ${specs.kill.debugPort})`);
  const killed = await killChromeForPort(specs.kill.debugPort);
  logProgress(`Killed ${killed.length} Chrome process(es): ${killed.join(", ")}`);
  const killStart = Date.now();
  await waitForDashboardReadiness(
    (payload) => {
      const session = payload.sessions?.find(
        (s) => s.sessionId === specs.kill.sessionId,
      );
      return !session || session.status === "closed";
    },
    `dashboard reflects ${specs.kill.sessionId} as closed/missing after Chrome kill`,
    killSlaMs,
  );
  logProgress(`Phase 1 passed: dashboard reflected kill within ${Date.now() - killStart} ms`);

  // Phase 2: close + reopen the same playwright-cli session WITHOUT restarting the dashboard
  logProgress(`Phase 2: opening restart-target CLI session ${specs.restart.sessionId}`);
  await openPlaywrightSession(specs.restart, specs.restart.server.rootURL);
  await loadRealSessionFile(specs.restart);
  logProgress(
    `${specs.restart.label} ready on CDP ${specs.restart.debugPort}; waiting for dashboard discovery`,
  );
  await waitForDashboardReadiness(
    (payload) =>
      payload.sessions?.some(
        (session) =>
          session.sessionId === specs.restart.sessionId && session.status !== "closed",
      ),
    `dashboard discovers ${specs.restart.sessionId} as active`,
    60_000,
  );

  logProgress(`Closing ${specs.restart.sessionId} via playwright-cli`);
  await closePlaywrightSession(specs.restart);
  await waitForDashboardReadiness(
    (payload) => {
      const session = payload.sessions?.find(
        (s) => s.sessionId === specs.restart.sessionId,
      );
      return !session || session.status === "closed";
    },
    `dashboard reflects ${specs.restart.sessionId} as closed/missing after CLI close`,
    killSlaMs,
  );
  logProgress("Closed and reflected; reopening same sessionId");

  // Clear cdpPort so we re-read after the new daemon assigns a fresh one.
  const previousPort = specs.restart.debugPort;
  specs.restart.debugPort = 0;
  specs.restart.sessionFile = null;
  await openPlaywrightSession(specs.restart, specs.restart.server.rootURL);
  await loadRealSessionFile(specs.restart);
  logProgress(
    `Restarted ${specs.restart.sessionId} on CDP ${specs.restart.debugPort} (was ${previousPort})`,
  );
  const restartStart = Date.now();
  await waitForDashboardReadiness(
    (payload) =>
      payload.sessions?.some(
        (session) =>
          session.sessionId === specs.restart.sessionId
          && session.status !== "closed"
          && session.cdpPort === specs.restart.debugPort,
      ),
    `dashboard rediscovers ${specs.restart.sessionId} with new CDP port ${specs.restart.debugPort}`,
    restartSlaMs,
  );
  logProgress(
    `Phase 2 passed: dashboard rediscovered restarted session within ${Date.now() - restartStart} ms (single long-lived dashboard process)`,
  );

  await quitApp();
  logProgress("Reliability smoke assertions passed");
  console.log("Reliability smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  for (const spec of Object.values(specs)) {
    await closePlaywrightSession(spec).catch(() => {});
    spec.server?.close();
  }
  await rm(tmpRoot, { recursive: true, force: true });
}

async function launchApp() {
  currentReadinessDir = path.join(readinessRoot, `launch-${++launchIndex}`);
  await rm(currentReadinessDir, { recursive: true, force: true });
  await mkdir(currentReadinessDir, { recursive: true });
  await run("open", [
    "-n",
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-in-memory-store",
    "--smoke-safe-mode",
    "--smoke-readiness-dir",
    currentReadinessDir,
  ]);
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

async function waitForDashboardReadiness(predicate, label, timeoutMs) {
  if (!currentReadinessDir) {
    throw new Error(`No readiness directory for ${label}`);
  }
  const filePath = path.join(currentReadinessDir, "dashboard-ready.json");
  const deadline = Date.now() + timeoutMs;
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
    timeout: 15_000,
  }).catch((error) => {
    return run("pkill", ["-f", `cli-daemon/program.js ${spec.sessionId}`]).catch(() => {
      console.warn(`Warning: failed to close ${spec.sessionId}: ${error.message}`);
    });
  });
}

async function killChromeForPort(port) {
  const { stdout } = await run("pgrep", ["-f", `--remote-debugging-port=${port}`], {
    timeout: 5_000,
  }).catch(() => ({ stdout: "" }));
  const pids = stdout
    .trim()
    .split(/\s+/)
    .filter((value) => /^\d+$/.test(value));
  if (pids.length === 0) {
    throw new Error(`No Chrome process found for debug port ${port}`);
  }
  for (const pid of pids) {
    await run("kill", ["-9", pid], { timeout: 5_000 }).catch(() => {});
  }
  return pids;
}

async function loadRealSessionFile(spec) {
  const deadline = Date.now() + 15_000;
  let sessionFile = null;
  while (Date.now() < deadline) {
    sessionFile = await findSessionFile(daemonRoot, `${spec.sessionId}.session`);
    if (sessionFile) break;
    await sleep(250);
  }
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function logProgress(message) {
  const stamped = `[${new Date().toISOString()}] ${message}`;
  console.log(stamped);
  progress.push(stamped);
}
