#!/usr/bin/env node

import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const artifactDir = process.env.SMOKE_ARTIFACT_DIR
  ? path.resolve(process.env.SMOKE_ARTIFACT_DIR)
  : null;
const tmpRoot = await mkdtemp(
  path.join(os.tmpdir(), "playwright-dashboard-cli-recording-smoke-"),
);
const daemonRoot = path.join(tmpRoot, "daemon");
const workspaceDir = path.join(tmpRoot, "workspace");
const resultPath = path.join(tmpRoot, "result.json");
const cliEnv = {
  ...process.env,
  PLAYWRIGHT_DAEMON_SESSION_DIR: daemonRoot,
  PWTEST_CLI_GLOBAL_CONFIG: path.join(tmpRoot, "no-global-config"),
};
const smokeId = String(process.pid);
const spec = {
  sessionId: `cli-rec-${smokeId}`,
  label: "CLI Recording",
  workspaceDir,
  debugPort: 0,
  sessionFile: null,
  server: null,
};

const progress = [];

try {
  logProgress("Cleaning up existing app process");
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);
  await mkdir(path.join(workspaceDir, ".playwright"), { recursive: true });

  logProgress("Checking playwright-cli availability");
  await ensurePlaywrightCLI();

  spec.server = await startAnimatedPageServer();
  logProgress(`Animated test page server listening at ${spec.server.rootURL}`);

  logProgress(`Opening Playwright CLI session ${spec.sessionId}`);
  await openPlaywrightSession(spec, spec.server.rootURL);
  await loadRealSessionFile(spec);
  logProgress(`${spec.label} ready as ${spec.sessionId} on CDP ${spec.debugPort}`);

  await waitForCDPPage(spec.debugPort, spec.server.rootURL);
  logProgress("CLI-spawned Chrome ready with target on test page");

  logProgress("Launching app for recording export");
  await run("open", [
    "-n",
    appPath,
    "--args",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-in-memory-store",
    "--smoke-disable-screenshots",
    "--smoke-session-id",
    spec.sessionId,
    "--smoke-recording-export-result",
    resultPath,
  ]);

  const result = await waitForResult();
  await assertResult(result);
  console.log(`Playwright CLI recording smoke passed: ${result.mp4Path}`);
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(() => {});
  await closePlaywrightSession(spec);
  spec.server?.close();
  await rm(tmpRoot, { recursive: true, force: true });
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

async function waitForCDPPage(port, expectedURL) {
  await waitFor(async () => {
    const list = await json(`http://127.0.0.1:${port}/json/list`).catch(() => []);
    return list.some((target) => target.type === "page" && target.url === expectedURL);
  }, `CDP page on port ${port}`);
}

async function waitForResult() {
  await waitFor(async () => {
    try {
      await stat(resultPath);
      return true;
    } catch {
      return false;
    }
  }, "recording export result", 60_000);
  return JSON.parse(await readFile(resultPath, "utf8"));
}

async function assertResult(result) {
  if (!result.success) {
    throw new Error(`CLI recording smoke failed: ${result.error ?? "unknown error"}`);
  }
  if (!result.recordingDirectory || !result.mp4Path) {
    throw new Error(`CLI recording smoke returned incomplete result: ${JSON.stringify(result)}`);
  }
  if (result.frameCount < 2) {
    throw new Error(`Expected at least two recorded frames, got ${result.frameCount}`);
  }
  const manifest = path.join(result.recordingDirectory, "manifest.json");
  const firstFrame = path.join(result.recordingDirectory, "frame-000001.jpg");
  for (const file of [manifest, firstFrame, result.mp4Path]) {
    const fileStat = await stat(file);
    if (fileStat.size <= 0) {
      throw new Error(`Expected non-empty recording artifact: ${file}`);
    }
  }
}

function startAnimatedPageServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((_request, response) => {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(`<!doctype html>
<html>
  <head>
    <title>CLI Recording Smoke</title>
    <style>
      body { margin: 0; font: 28px -apple-system, BlinkMacSystemFont, sans-serif; }
      main { min-height: 100vh; display: grid; place-items: center; background: #102030; color: white; }
      output { font-variant-numeric: tabular-nums; }
    </style>
  </head>
  <body>
    <main><output id="counter">0</output></main>
    <script>
      const counter = document.getElementById('counter');
      let value = 0;
      setInterval(() => {
        value += 1;
        counter.textContent = String(value);
        document.body.style.backgroundColor = value % 2 ? '#204060' : '#102030';
      }, 150);
    </script>
  </body>
</html>`);
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

async function writeSmokeArtifacts(error) {
  if (!artifactDir) return;
  try {
    await mkdir(artifactDir, { recursive: true });
    await writeFile(
      path.join(artifactDir, "progress.json"),
      JSON.stringify({ progress, error: String(error?.stack ?? error) }, null, 2),
    );
    try {
      const data = await readFile(resultPath);
      await writeFile(path.join(artifactDir, "result.json"), data);
    } catch {
      // result file may not exist yet
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

async function waitFor(predicate, label, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await sleep(500);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function logProgress(message) {
  const stamped = `[${new Date().toISOString()}] ${message}`;
  console.log(stamped);
  progress.push(stamped);
}
