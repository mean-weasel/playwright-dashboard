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
const sessionCount = Math.max(
  2,
  Number.parseInt(process.env.MANY_SESSION_COUNT ?? "12", 10) || 12,
);
const discoverySlaMs = Number.parseInt(process.env.MANY_SESSION_DISCOVERY_SLA_MS ?? "120000", 10);
const cleanupSlaMs = Number.parseInt(process.env.MANY_SESSION_CLEANUP_SLA_MS ?? "60000", 10);
const expandedTimeoutMs = Number.parseInt(
  process.env.MANY_SESSION_EXPANDED_TIMEOUT_MS ?? "30000",
  10,
);
const accessibilityHelp = staticAccessibilityHelp();
const tmpRoot = await mkdtemp(
  path.join(os.tmpdir(), "playwright-dashboard-many-sessions-smoke-"),
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

const specs = Array.from({ length: sessionCount }, (_, index) => ({
  index,
  sessionId: `cli-many-${String(index).padStart(2, "0")}-${smokeId}`,
  label: `Many ${String(index + 1).padStart(2, "0")}`,
  workspaceDir,
  debugPort: 0,
  sessionFile: null,
  server: null,
}));

let appOpened = false;
let currentReadinessDir = null;
let launchIndex = 0;
const progress = [];
const resourceSamples = [];
let resourceSamplerHandle = null;

await runGuiPreflight();
logProgress("Accessibility preflight passed");

const phaseTimings = {};

try {
  logProgress("Cleaning up existing app process");
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);
  await mkdir(path.join(workspaceDir, ".playwright"), { recursive: true });
  await ensurePlaywrightCLI();

  logProgress(`Starting ${sessionCount} HTTP servers + playwright-cli sessions`);
  const setupStart = Date.now();
  for (const spec of specs) {
    spec.server = await startSessionServer(spec);
    await openPlaywrightSession(spec, spec.server.rootURL);
    await loadRealSessionFile(spec);
    logProgress(
      `${spec.label} ready as ${spec.sessionId} on CDP ${spec.debugPort} (${spec.server.rootURL})`,
    );
  }
  phaseTimings.setupMs = Date.now() - setupStart;
  logProgress(`Phase 1 (setup) took ${phaseTimings.setupMs} ms`);

  logProgress("Disabling persisted control mode default");
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  // Phase 2: dashboard discovers all sessions within SLA
  logProgress(`Phase 2: launching dashboard to discover all ${sessionCount} sessions`);
  const discoverStart = Date.now();
  await launchApp();
  startResourceSampler();
  const discoveryPayload = await waitForReadinessPayload(
    "dashboard-ready.json",
    (payload) => {
      if (payload.safeMode !== true) return false;
      if (!Array.isArray(payload.sessions)) return false;
      const sessionsById = new Map(payload.sessions.map((s) => [s.sessionId, s]));
      return specs.every((spec) => {
        const session = sessionsById.get(spec.sessionId);
        return (
          session?.lastTitle === spec.label
          && session.cdpPort === spec.debugPort
        );
      });
    },
    `dashboard discovers all ${sessionCount} sessions`,
    discoverySlaMs,
  );
  phaseTimings.discoveryMs = Date.now() - discoverStart;
  stopResourceSampler();
  logProgress(
    `Phase 2 (discovery) took ${phaseTimings.discoveryMs} ms; payload reports ${discoveryPayload.sessions.length} sessions`,
  );
  await quitApp();

  // Phase 3: open each expanded view in sequence to verify the dashboard doesn't hang
  logProgress("Phase 3: opening each session's expanded view in sequence");
  const expandedStart = Date.now();
  for (const spec of specs) {
    const launchStart = Date.now();
    await launchApp(spec.sessionId);
    await waitForReadinessPayload(
      "expanded-ready.json",
      (payload) =>
        payload.session?.sessionId === spec.sessionId
        && payload.safeMode === true,
      `expanded view for ${spec.sessionId}`,
      expandedTimeoutMs,
    );
    await quitApp();
    const elapsed = Date.now() - launchStart;
    logProgress(`  expanded view ${spec.sessionId}: ${elapsed} ms`);
  }
  phaseTimings.expandedTotalMs = Date.now() - expandedStart;
  phaseTimings.expandedAvgMs = Math.round(phaseTimings.expandedTotalMs / specs.length);
  logProgress(
    `Phase 3 (expanded views) took ${phaseTimings.expandedTotalMs} ms total, ${phaseTimings.expandedAvgMs} ms/session avg`,
  );

  // Phase 4: close all sessions; dashboard returns to no-active-sessions within SLA
  logProgress("Phase 4: closing all CLI sessions");
  const cleanupStart = Date.now();
  await Promise.all(specs.map((spec) => closePlaywrightSession(spec)));
  await launchApp();
  const cleanupPayload = await waitForReadinessPayload(
    "dashboard-ready.json",
    (payload) => {
      if (!Array.isArray(payload.sessions)) return false;
      const knownIds = new Set(specs.map((s) => s.sessionId));
      const knownSessions = payload.sessions.filter((s) => knownIds.has(s.sessionId));
      const stillActive = knownSessions.filter((s) => s.status !== "closed");
      return stillActive.length === 0;
    },
    `dashboard reports all ${sessionCount} sessions as closed/missing`,
    cleanupSlaMs,
  );
  phaseTimings.cleanupMs = Date.now() - cleanupStart;
  await quitApp();
  logProgress(
    `Phase 4 (cleanup) took ${phaseTimings.cleanupMs} ms; payload still references ${cleanupPayload.sessions.length} session records (all in closed/missing state)`,
  );

  await emitResourceSummary();
  logProgress("Many-sessions stress smoke assertions passed");
  console.log(
    `Many-sessions stress smoke passed: ${sessionCount} sessions, discovery ${phaseTimings.discoveryMs} ms, cleanup ${phaseTimings.cleanupMs} ms`,
  );
} catch (error) {
  stopResourceSampler();
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  for (const spec of specs) {
    await closePlaywrightSession(spec).catch(() => {});
    spec.server?.close();
  }
  await rm(tmpRoot, { recursive: true, force: true });
}

async function launchApp(selectedSessionId = null) {
  currentReadinessDir = path.join(readinessRoot, `launch-${++launchIndex}`);
  await rm(currentReadinessDir, { recursive: true, force: true });
  await mkdir(currentReadinessDir, { recursive: true });
  const appArgs = [
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
  ];
  if (selectedSessionId) {
    appArgs.push("--smoke-session-id", selectedSessionId);
  }
  await run("open", appArgs);
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

async function waitForReadinessPayload(filename, predicate, label, timeoutMs) {
  if (!currentReadinessDir) {
    throw new Error(`No readiness directory for ${label}`);
  }
  const filePath = path.join(currentReadinessDir, filename);
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

function startResourceSampler() {
  resourceSamples.length = 0;
  resourceSamplerHandle = setInterval(async () => {
    try {
      const { stdout } = await run("pgrep", ["-x", "PlaywrightDashboard"], { timeout: 2_000 });
      const pid = stdout.trim().split(/\s+/)[0];
      if (!pid) return;
      const psResult = await run("ps", ["-o", "rss=,%cpu=", "-p", pid], { timeout: 2_000 });
      const [rssStr, cpuStr] = psResult.stdout.trim().split(/\s+/);
      const rssKb = Number.parseInt(rssStr, 10);
      const cpu = Number.parseFloat(cpuStr);
      if (Number.isFinite(rssKb) && Number.isFinite(cpu)) {
        resourceSamples.push({ at: Date.now(), rssKb, cpu });
      }
    } catch {
      // ignore — process may be transitioning
    }
  }, 1_000);
}

function stopResourceSampler() {
  if (resourceSamplerHandle) {
    clearInterval(resourceSamplerHandle);
    resourceSamplerHandle = null;
  }
}

async function emitResourceSummary() {
  if (resourceSamples.length === 0) {
    logProgress("No resource samples collected");
    return;
  }
  const rss = resourceSamples.map((s) => s.rssKb);
  const cpu = resourceSamples.map((s) => s.cpu);
  const peakRssMb = Math.round(Math.max(...rss) / 1024);
  const avgRssMb = Math.round(rss.reduce((a, b) => a + b, 0) / rss.length / 1024);
  const peakCpu = Math.max(...cpu).toFixed(1);
  const avgCpu = (cpu.reduce((a, b) => a + b, 0) / cpu.length).toFixed(1);

  const summary = {
    sessionCount,
    sampleCount: resourceSamples.length,
    rssMb: { peak: peakRssMb, average: avgRssMb },
    cpuPercent: { peak: peakCpu, average: avgCpu },
    phaseTimingsMs: phaseTimings,
  };

  if (artifactDir) {
    await mkdir(artifactDir, { recursive: true });
    await writeFile(
      path.join(artifactDir, "resource-summary.json"),
      `${JSON.stringify(summary, null, 2)}\n`,
    );
  }

  const stepSummary = process.env.GITHUB_STEP_SUMMARY;
  if (stepSummary) {
    const lines = [
      `## Many-sessions stress smoke (${sessionCount} sessions)`,
      "",
      "| Metric | Peak | Average |",
      "| --- | ---: | ---: |",
      `| Dashboard RSS | ${peakRssMb} MB | ${avgRssMb} MB |`,
      `| Dashboard CPU | ${peakCpu}% | ${avgCpu}% |`,
      "",
      "| Phase | Duration |",
      "| --- | ---: |",
      `| Setup (open ${sessionCount} CLI sessions) | ${phaseTimings.setupMs ?? "-"} ms |`,
      `| Discovery | ${phaseTimings.discoveryMs ?? "-"} ms |`,
      `| Expanded views (sequential) | ${phaseTimings.expandedTotalMs ?? "-"} ms total / ${phaseTimings.expandedAvgMs ?? "-"} ms avg |`,
      `| Cleanup | ${phaseTimings.cleanupMs ?? "-"} ms |`,
      "",
    ];
    await writeFile(stepSummary, lines.join("\n") + "\n", { flag: "a" });
  }
  logProgress(`Resource summary: peak RSS ${peakRssMb} MB, peak CPU ${peakCpu}%`);
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
      JSON.stringify(
        { progress, error: String(error?.stack ?? error), phaseTimings, resourceSamples },
        null,
        2,
      ),
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
