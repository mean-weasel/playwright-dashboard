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
const tmpRoot = await fsTempDir("playwright-dashboard-multi-target-smoke-");
const daemonRoot = path.join(tmpRoot, "daemon");
const readinessRoot = path.join(tmpRoot, "readiness");
const workspaceDir = path.join(tmpRoot, "workspace");
const cliEnv = {
  ...process.env,
  PLAYWRIGHT_DAEMON_SESSION_DIR: daemonRoot,
  PWTEST_CLI_GLOBAL_CONFIG: path.join(tmpRoot, "no-global-config"),
};
const smokeId = String(process.pid);
const spec = {
  slug: "alpha",
  sessionId: `cli-mt-a-${smokeId}`,
  label: "MultiTarget Alpha",
  workspaceDir,
  debugPort: 0,
  sessionFile: null,
  serverA: null,
  serverB: null,
};

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

  spec.serverA = await startSessionServer("A");
  spec.serverB = await startSessionServer("B");

  logProgress(`Opening Playwright CLI session against ${spec.serverA.rootURL}`);
  await openPlaywrightSession(spec, spec.serverA.rootURL);
  await loadRealSessionFile(spec);
  logProgress(`${spec.label} ready as ${spec.sessionId} on CDP ${spec.debugPort}`);

  logProgress(`Adding second tab via CDP /json/new -> ${spec.serverB.rootURL}`);
  const newTab = await cdpJSONNew(spec.debugPort, spec.serverB.rootURL);
  const tabBId = newTab.id;
  if (!tabBId) throw new Error(`/json/new returned no id: ${JSON.stringify(newTab)}`);

  const targets = await waitForCDPTargets(spec.debugPort, 2);
  const tabA = targets.find(
    (target) => target.id !== tabBId && target.type === "page",
  );
  if (!tabA) throw new Error(`Did not find original target alongside ${tabBId}`);
  const tabAId = tabA.id;
  logProgress(`Targets: A=${tabAId} (${tabA.url}) B=${tabBId} (${newTab.url})`);

  logProgress("Disabling persisted control mode default");
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  // Phase G1: expanded view shows pageTargetCount=2
  logProgress("Phase G1: expanded view discovers both targets");
  await launchExpandedView({});
  await waitForExpandedReadiness(
    (payload) =>
      payload.session?.sessionId === spec.sessionId
      && payload.session?.pageTargetCount >= 2,
    `expanded view reports pageTargetCount>=2 for ${spec.sessionId}`,
  );
  await quitApp();
  logProgress("Phase G1 passed: both targets surfaced in expanded view");

  // Phase G2: switch selected target to B
  logProgress(`Phase G2: switching selected target to ${tabBId}`);
  await launchExpandedView({
    extraArgs: ["--smoke-select-target-id", tabBId],
  });
  await waitForExpandedReadiness(
    (payload) =>
      payload.session?.sessionId === spec.sessionId
      && payload.session?.selectedTargetId === tabBId
      && payload.session?.pageTargetCount >= 2,
    `expanded view reports selectedTargetId=${tabBId}`,
  );
  await quitApp();
  logProgress("Phase G2 passed: target switch reflected in readiness payload");

  // Phase G3: close tab A; assert B remains selected with pageTargetCount=1
  logProgress(`Phase G3: closing tab A (${tabAId}) and confirming B remains selected`);
  await cdpJSONClose(spec.debugPort, tabAId);
  await waitForCDPTargets(spec.debugPort, 1);
  await launchExpandedView({
    extraArgs: ["--smoke-select-target-id", tabBId],
  });
  await waitForExpandedReadiness(
    (payload) =>
      payload.session?.sessionId === spec.sessionId
      && payload.session?.selectedTargetId === tabBId
      && payload.session?.pageTargetCount === 1,
    `expanded view shows pageTargetCount=1 with ${tabBId} still selected`,
  );
  await quitApp();
  logProgress("Phase G3 passed: non-selected tab closed cleanly, active target intact");

  logProgress("Playwright CLI multi-target smoke assertions passed");
  console.log("Playwright CLI multi-target smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  await closePlaywrightSession(spec);
  spec.serverA?.close();
  spec.serverB?.close();
  await rm(tmpRoot, { recursive: true, force: true });
}

async function launchExpandedView({ extraArgs = [] } = {}) {
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
    "--smoke-session-id",
    spec.sessionId,
    ...extraArgs,
  ];
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

async function waitForExpandedReadiness(predicate, label) {
  if (!currentReadinessDir) {
    throw new Error(`No readiness directory for ${label}`);
  }
  const filePath = path.join(currentReadinessDir, "expanded-ready.json");
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

async function openPlaywrightSession(s, url) {
  await runPlaywrightCLI(
    [`-s=${s.sessionId}`, "open", url, "--browser=chrome", "--headed"],
    { cwd: workspaceDir, timeout: 120_000 },
  );
}

async function closePlaywrightSession(s) {
  await runPlaywrightCLI([`-s=${s.sessionId}`, "close"], {
    cwd: workspaceDir,
    timeout: 10_000,
  }).catch((error) => {
    return run("pkill", ["-f", `cli-daemon/program.js ${s.sessionId}`]).catch(() => {
      console.warn(`Warning: failed to close ${s.sessionId}: ${error.message}`);
    });
  });
}

async function loadRealSessionFile(s) {
  const sessionFile = await findSessionFile(daemonRoot, `${s.sessionId}.session`);
  if (!sessionFile) {
    throw new Error(`playwright-cli did not create ${s.sessionId}.session under ${daemonRoot}`);
  }
  const config = JSON.parse(await readFile(sessionFile, "utf8"));
  const cdpPort = config.browser?.launchOptions?.cdpPort;
  if (!Number.isInteger(cdpPort) || cdpPort <= 0) {
    throw new Error(`${s.sessionId}.session does not contain a usable CDP port`);
  }
  s.debugPort = cdpPort;
  s.sessionFile = sessionFile;
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

function startSessionServer(slug) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((_request, response) => {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(
        `<!doctype html><html><head><title>Multi-target ${slug}</title></head><body><h1>${slug}</h1></body></html>`,
      );
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      resolve({
        slug,
        port,
        rootURL: `http://127.0.0.1:${port}/`,
        close: () => server.close(),
      });
    });
  });
}

function cdpJSONNew(port, targetURL) {
  return cdpJSONRequest(port, `/json/new?${encodeURI(targetURL)}`, "PUT");
}

function cdpJSONClose(port, targetId) {
  return cdpJSONRequest(port, `/json/close/${encodeURIComponent(targetId)}`, "PUT");
}

function cdpJSONRequest(port, urlPath, method) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: "127.0.0.1",
        port,
        path: urlPath,
        method,
        headers: { Host: "127.0.0.1" },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          if ((res.statusCode ?? 0) >= 400) {
            reject(
              new Error(
                `CDP ${method} ${urlPath} returned ${res.statusCode}: ${data.slice(0, 200)}`,
              ),
            );
            return;
          }
          if (!data.trim()) {
            resolve({});
            return;
          }
          try {
            resolve(JSON.parse(data));
          } catch (error) {
            resolve({ raw: data });
          }
        });
      },
    );
    req.on("error", reject);
    req.end();
  });
}

async function waitForCDPTargets(port, expectedPageCount) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const list = await json(`http://127.0.0.1:${port}/json/list`).catch(() => []);
    const pages = list.filter((target) => target.type === "page");
    if (pages.length === expectedPageCount) return pages;
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${expectedPageCount} CDP page targets on port ${port}`);
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

async function json(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (response) => {
        let data = "";
        response.on("data", (chunk) => {
          data += chunk;
        });
        response.on("end", () => {
          try {
            resolve(JSON.parse(data));
          } catch (error) {
            reject(error);
          }
        });
      })
      .on("error", reject);
  });
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
