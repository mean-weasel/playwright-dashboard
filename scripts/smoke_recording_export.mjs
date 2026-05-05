#!/usr/bin/env node

import { execFile, spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const sessionName = `smoke-recording-${process.pid}`;

const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "playwright-dashboard-recording-smoke-"));
const daemonRoot = path.join(tmpRoot, "daemon");
const daemonDir = path.join(daemonRoot, `codex-recording-${process.pid}`);
const resultURL = path.join(tmpRoot, "result.json");

let chromeProcess;
let server;

try {
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  server = await startPageServer();
  const pageURL = `http://127.0.0.1:${server.port}/`;
  const debugPort = await freePort();
  const chromePath =
    process.env.CHROME_PATH ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

  chromeProcess = spawn(chromePath, [
    `--user-data-dir=${path.join(tmpRoot, "chrome-profile")}`,
    `--remote-debugging-port=${debugPort}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    pageURL,
  ], { stdio: "ignore" });

  await waitFor(async () => {
    const pages = await json(`http://127.0.0.1:${debugPort}/json/list`).catch(() => []);
    return pages.some((page) => page.url === pageURL);
  }, "Chrome CDP page");

  await createSessionFile(debugPort);
  await run("open", [
    appPath,
    "--args",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-in-memory-store",
    "--smoke-disable-screenshots",
    "--smoke-session-id",
    sessionName,
    "--smoke-recording-export-result",
    resultURL,
  ]);

  const result = await waitForResult();
  await assertResult(result);
  console.log(`Recording export smoke passed: ${result.mp4Path}`);
} finally {
  await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(() => {});
  await stopChrome();
  server?.close();
  await rm(tmpRoot, { recursive: true, force: true });
}

async function createSessionFile(debugPort) {
  await mkdir(daemonDir, { recursive: true });
  const session = {
    name: sessionName,
    version: "1",
    timestamp: Date.now(),
    socketPath: path.join(tmpRoot, "playwright.sock"),
    workspaceDir: path.join(tmpRoot, "smoke-recording"),
    cli: {},
    browser: {
      browserName: "chromium",
      launchOptions: {
        headless: false,
        chromiumSandbox: false,
        cdpPort: debugPort,
      },
    },
  };
  await writeFile(path.join(daemonDir, `${sessionName}.session`), `${JSON.stringify(session)}\n`);
}

async function waitForResult() {
  await waitFor(async () => {
    try {
      await stat(resultURL);
      return true;
    } catch {
      return false;
    }
  }, "recording export result", 45_000);
  return JSON.parse(await readFile(resultURL, "utf8"));
}

async function assertResult(result) {
  if (!result.success) {
    throw new Error(`Recording export smoke failed: ${result.error ?? "unknown error"}`);
  }
  if (!result.recordingDirectory || !result.mp4Path) {
    throw new Error(`Recording export smoke returned incomplete result: ${JSON.stringify(result)}`);
  }
  if (result.frameCount < 2) {
    throw new Error(`Expected at least two recorded frames, got ${result.frameCount}`);
  }
  const manifest = path.join(result.recordingDirectory, "manifest.json");
  const frame = path.join(result.recordingDirectory, "frame-000001.jpg");
  for (const file of [manifest, frame, result.mp4Path]) {
    const fileStat = await stat(file);
    if (fileStat.size <= 0) {
      throw new Error(`Expected non-empty recording artifact: ${file}`);
    }
  }
}

function startPageServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(`<!doctype html>
<html>
  <head>
    <title>Recording Export Smoke</title>
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
      resolve({ server, port: server.address().port, close: () => server.close() });
    });
  });
}

async function stopChrome() {
  if (!chromeProcess || chromeProcess.exitCode !== null) return;
  chromeProcess.kill("SIGTERM");
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 2_000);
    chromeProcess.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

async function json(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} returned ${response.status}`);
  return response.json();
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

function freePort() {
  return new Promise((resolve, reject) => {
    const server = http.createServer();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
  });
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { cwd: repoRoot, ...options }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`${command} failed: ${stderr || stdout || error.message}`));
        return;
      }
      resolve(stdout);
    });
  });
}
