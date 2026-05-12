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
const teardownSettleMs = Number.parseInt(
  process.env.RELIABILITY_TEARDOWN_SETTLE_MS ?? "5000",
  10,
);
const sleepDurationMs = Number.parseInt(
  process.env.RELIABILITY_SLEEP_DURATION_MS ?? "12000",
  10,
);
const wakeRecoverySlaMs = Number.parseInt(
  process.env.RELIABILITY_WAKE_RECOVERY_SLA_MS ?? "30000",
  10,
);
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

// Keep session ids short — macOS Unix sockets cap `sun_path` at 104 bytes
// and the daemon socket path lives under `/var/folders/.../T/pw-<8>/cli/`
// which already consumes ~65 bytes on CI runners. A 21-char session id
// (e.g. `cli-rel-restart-<pid>`) plus the workspace-hash prefix pushed the
// full path to 108 bytes on macos-15 runners, where the kernel silently
// truncates to 104, the daemon ends up bound to a `<name>.` file (no
// `.sock`), the .session file still records `<name>.sock`, and the
// next bind() collides on the truncated path → EADDRINUSE. Local repros
// pass because $TMPDIR is shorter.
const specs = {
  kill: {
    slug: "kill",
    sessionId: `rk-${smokeId}`,
    label: "Reliability Kill",
    debugPort: 0,
    sessionFile: null,
    socketPath: null,
    server: null,
  },
  restart: {
    slug: "restart",
    sessionId: `rr-${smokeId}`,
    label: "Reliability Restart",
    debugPort: 0,
    sessionFile: null,
    socketPath: null,
    server: null,
  },
  sleepwake: {
    slug: "sleepwake",
    sessionId: `rw-${smokeId}`,
    label: "Reliability SleepWake",
    debugPort: 0,
    sessionFile: null,
    socketPath: null,
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

  for (const s of Object.values(specs)) {
    s.server = await startSessionServer(s);
  }

  logProgress(`Opening kill-target CLI session ${specs.kill.sessionId}`);
  await openPlaywrightSession(specs.kill, specs.kill.server.rootURL);
  await loadRealSessionFile(specs.kill);
  logProgress(`${specs.kill.label} ready on CDP ${specs.kill.debugPort}`);

  logProgress(`Opening sleep/wake-target CLI session ${specs.sleepwake.sessionId}`);
  await openPlaywrightSession(specs.sleepwake, specs.sleepwake.server.rootURL);
  await loadRealSessionFile(specs.sleepwake);
  logProgress(`${specs.sleepwake.label} ready on CDP ${specs.sleepwake.debugPort}`);

  logProgress("Disabling persisted control mode default");
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  logProgress("Launching dashboard");
  await launchApp();

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
      const session = payload.sessions?.find((s) => s.sessionId === specs.kill.sessionId);
      return !session || session.status === "closed";
    },
    `dashboard reflects ${specs.kill.sessionId} as closed/missing after Chrome kill`,
    killSlaMs,
  );
  logProgress(`Phase 1 passed: dashboard reflected kill within ${Date.now() - killStart} ms`);

  // Phase 2 (diagnostic): tear down with SIGKILL + manual rm, then dump
  // filesystem state at the moment of reopen so we can see exactly what is
  // blocking the bind() on macos-15.
  logProgress(`Phase 2: opening restart-target ${specs.restart.sessionId}`);
  await openPlaywrightSession(specs.restart, specs.restart.server.rootURL);
  await loadRealSessionFile(specs.restart);
  logProgress(`${specs.restart.label} ready on CDP ${specs.restart.debugPort}`);
  await waitForDashboardReadiness(
    (payload) =>
      payload.sessions?.some(
        (session) =>
          session.sessionId === specs.restart.sessionId && session.status !== "closed",
      ),
    `dashboard discovers ${specs.restart.sessionId} as active`,
    60_000,
  );

  logProgress(`Tearing down ${specs.restart.sessionId} (SIGKILL + manual cleanup)`);
  await dumpSocketState("PRE-TEARDOWN", specs.restart);
  await sigkillDaemonAndCleanup(specs.restart);
  await dumpSocketState("POST-CLEANUP", specs.restart);
  logProgress(`Settling ${teardownSettleMs} ms before reopen`);
  await sleep(teardownSettleMs);
  await dumpSocketState("POST-SETTLE", specs.restart);

  const previousPort = specs.restart.debugPort;
  specs.restart.debugPort = 0;
  specs.restart.sessionFile = null;
  specs.restart.socketPath = null;
  try {
    await openPlaywrightSession(specs.restart, specs.restart.server.rootURL);
  } catch (error) {
    await dumpSocketState("REOPEN-FAILURE", specs.restart);
    throw error;
  }
  await loadRealSessionFile(specs.restart);
  logProgress(
    `Reopened ${specs.restart.sessionId} on CDP ${specs.restart.debugPort} (was ${previousPort})`,
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
    `dashboard rediscovers ${specs.restart.sessionId} with new CDP port`,
    restartSlaMs,
  );
  logProgress(`Phase 2 passed: rediscovered within ${Date.now() - restartStart} ms`);

  await quitApp();

  // Phase 3: sleep/wake CDP reconnect. Simulate sleep by SIGSTOPping the
  // Chrome process — the CDP TCP server is part of Chrome's main process, so
  // a stopped Chrome looks exactly like a sleeping device from the
  // dashboard's perspective: no I/O on the WebSocket. Wake with SIGCONT and
  // assert the dashboard exits the disconnected state — either reconnecting
  // screencast or falling back to snapshot polling, but not stuck in
  // `connectionLost`.
  logProgress(`Phase 3: launching dashboard with ${specs.sleepwake.sessionId} in expanded view`);
  await launchApp(specs.sleepwake.sessionId);
  await waitForExpandedReadiness(
    (payload) =>
      payload.session?.sessionId === specs.sleepwake.sessionId
      && typeof payload.frameMode === "string"
      && payload.frameMode !== "connectionLost",
    `expanded view reaches a non-disconnected frameMode for ${specs.sleepwake.sessionId}`,
    60_000,
  );
  const initialPayload = await readExpandedReadiness();
  logProgress(
    `Phase 3 initial state: frameMode=${initialPayload.frameMode}, targetMonitorMode=${initialPayload.targetMonitorMode}`,
  );

  logProgress(`SIGSTOP Chrome (port ${specs.sleepwake.debugPort}) to simulate sleep`);
  const stoppedPids = await signalChromeForPort(specs.sleepwake.debugPort, "STOP");
  logProgress(`Stopped ${stoppedPids.length} Chrome PID(s): ${stoppedPids.join(", ")}`);
  logProgress(`Sleeping ${sleepDurationMs} ms before resuming`);
  await sleep(sleepDurationMs);

  logProgress(`SIGCONT Chrome (port ${specs.sleepwake.debugPort}) to simulate wake`);
  await signalChromeForPort(specs.sleepwake.debugPort, "CONT");
  const recoveryStart = Date.now();
  const recovered = await waitForExpandedReadiness(
    (payload) =>
      payload.session?.sessionId === specs.sleepwake.sessionId
      && (payload.frameMode === "liveScreencast"
        || payload.frameMode === "snapshotFallback"),
    `dashboard recovers from sleep (frameMode in {liveScreencast, snapshotFallback}) for ${specs.sleepwake.sessionId}`,
    wakeRecoverySlaMs,
  );
  logProgress(
    `Phase 3 passed: dashboard recovered after wake in ${Date.now() - recoveryStart} ms (frameMode=${recovered.frameMode}, targetMonitorMode=${recovered.targetMonitorMode})`,
  );

  await quitApp();
  logProgress("Reliability smoke assertions passed");
  console.log("Reliability smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  for (const s of Object.values(specs)) {
    await closePlaywrightSession(s).catch(() => {});
    s.server?.close();
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

async function waitForDashboardReadiness(predicate, label, timeoutMs) {
  return waitForReadinessPayload("dashboard-ready.json", predicate, label, timeoutMs);
}

async function waitForExpandedReadiness(predicate, label, timeoutMs) {
  return waitForReadinessPayload("expanded-ready.json", predicate, label, timeoutMs);
}

async function readExpandedReadiness() {
  if (!currentReadinessDir) return null;
  return readJSONFile(path.join(currentReadinessDir, "expanded-ready.json")).catch(() => null);
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

async function killChromeForPort(port) {
  return signalChromeForPort(port, "KILL");
}

async function signalChromeForPort(port, signal) {
  // pgrep parses patterns starting with `--` as flags unless we pass `--` first
  // to terminate option parsing.
  const { stdout } = await run("pgrep", ["-f", "--", `--remote-debugging-port=${port}`], {
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
    await run("kill", [`-${signal}`, pid], { timeout: 5_000 }).catch(() => {});
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
  spec.socketPath = config.socketPath ?? null;
}

async function sigkillDaemonAndCleanup(spec) {
  const pattern = `cli-daemon.*${spec.sessionId}`;
  const { stdout } = await run("pgrep", ["-f", "--", pattern], { timeout: 5_000 }).catch(
    () => ({ stdout: "" }),
  );
  const daemonPids = stdout
    .trim()
    .split(/\s+/)
    .filter((value) => /^\d+$/.test(value));
  logProgress(`  daemon pids: ${daemonPids.join(", ") || "(none)"}`);
  for (const pid of daemonPids) {
    await run("kill", ["-9", pid], { timeout: 5_000 }).catch(() => {});
  }
  await killChromeForPort(spec.debugPort).catch(() => {});
  if (spec.socketPath) {
    await rm(spec.socketPath, { force: true }).catch(() => {});
  }
  if (spec.sessionFile) {
    await rm(spec.sessionFile, { force: true }).catch(() => {});
  }
}

async function dumpSocketState(label, spec) {
  const lines = [`  [${label}] socketPath: ${spec.socketPath ?? "(unknown)"}`];
  if (spec.socketPath) {
    try {
      const st = await import("node:fs/promises").then((m) => m.stat(spec.socketPath));
      lines.push(`    file exists: yes, mode=${st.mode.toString(8)}, size=${st.size}`);
    } catch (error) {
      lines.push(`    file exists: NO (${error.code || error.message})`);
    }
    const socketDir = path.dirname(spec.socketPath);
    try {
      const dirEntries = await readdir(socketDir);
      const related = dirEntries.filter((entry) => entry.includes(spec.sessionId));
      lines.push(`    matching entries in ${socketDir}: ${related.join(", ") || "(none)"}`);
    } catch (error) {
      lines.push(`    socket dir read failed: ${error.message}`);
    }
    const { stdout } = await run("lsof", ["--", spec.socketPath], { timeout: 5_000 }).catch(
      (error) => ({ stdout: `lsof failed: ${error.message}` }),
    );
    const lsofTrimmed = stdout.trim();
    if (lsofTrimmed) {
      lines.push(`    lsof:\n${lsofTrimmed.split("\n").map((l) => `      ${l}`).join("\n")}`);
    } else {
      lines.push("    lsof: (no output)");
    }
  }
  const pgrepDaemon = await run("pgrep", ["-fl", "--", `cli-daemon.*${spec.sessionId}`], {
    timeout: 3_000,
  }).catch(() => ({ stdout: "" }));
  lines.push(`    pgrep cli-daemon.*${spec.sessionId}: ${pgrepDaemon.stdout.trim() || "(none)"}`);
  for (const line of lines) logProgress(line);
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
