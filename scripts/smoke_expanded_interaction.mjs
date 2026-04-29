#!/usr/bin/env node

import { execFile, spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const sessionName = `smoke-interaction-${process.pid}`;
const displayName = "Smoke Interaction";
const tmpRoot = await fsTempDir("playwright-dashboard-expanded-smoke-");
const daemonDir = path.join(
  os.homedir(),
  "Library",
  "Caches",
  "ms-playwright",
  "daemon",
  `codex-expanded-interaction-${process.pid}`,
);
const sessionPath = path.join(daemonDir, `${sessionName}.session`);

let chromeProcess;
let appOpened = false;
let server;

try {
  const events = [];
  server = await startEventServer(events);
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
  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  await run("open", [
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-session-id",
    sessionName,
  ]);
  appOpened = true;
  let point;
  try {
    point = await runAppleScript(uiScript());
  } catch (error) {
    const snapshot = await runAppleScript(uiSnapshotScript()).catch((snapshotError) => {
      return `Unable to collect UI snapshot: ${snapshotError.message}`;
    });
    console.error(snapshot);
    throw error;
  }
  const [x, y] = point.match(/-?\d+(?:\.\d+)?/g)?.map(Number) ?? [];
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    throw new Error(`Invalid screenshot coordinates from AppleScript: ${point}`);
  }

  await run(path.join(repoRoot, "scripts", "post_pointer_events.swift"), [String(x), String(y)]);

  await waitFor(() => {
    const types = new Set(events.map((event) => event.type));
    return types.has("click") && types.has("wheel");
  }, "page click and wheel events");

  console.log("Expanded interaction smoke passed");
} finally {
  if (appOpened) {
    await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(
      () => {},
    );
  }
  chromeProcess?.kill("SIGTERM");
  server?.close();
  await rm(daemonDir, { recursive: true, force: true });
  await rm(tmpRoot, { recursive: true, force: true });
}

async function fsTempDir(prefix) {
  const { mkdtemp } = await import("node:fs/promises");
  return mkdtemp(path.join(os.tmpdir(), prefix));
}

async function createSessionFile(debugPort) {
  await mkdir(daemonDir, { recursive: true });
  const session = {
    name: sessionName,
    version: "1",
    timestamp: Date.now(),
    socketPath: path.join(tmpRoot, "playwright.sock"),
    workspaceDir: path.join(tmpRoot, "smoke-interaction"),
    cli: {},
    browser: {
      browserName: "chromium",
      launchOptions: {
        headless: false,
        chromiumSandbox: false,
        args: [`--remote-debugging-port=${debugPort}`],
      },
    },
  };
  await writeFile(sessionPath, `${JSON.stringify(session)}\n`, "utf8");
}

function startEventServer(events) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      const url = new URL(request.url, "http://127.0.0.1");
      if (url.pathname === "/event") {
        events.push({ type: url.searchParams.get("type"), at: Date.now() });
        response.writeHead(204);
        response.end();
        return;
      }
      if (url.pathname === "/events.json") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify(events));
        return;
      }
      response.writeHead(200, { "content-type": "text/html" });
      response.end(testPage());
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: server.address().port, close: () => server.close() });
    });
  });
}

function testPage() {
  return `<!doctype html>
<html>
  <head>
    <title>${displayName}</title>
    <style>
      body { margin: 0; font: 16px -apple-system, BlinkMacSystemFont, sans-serif; }
      main { min-height: 220vh; padding: 80px; }
      button { font-size: 24px; padding: 24px 32px; }
    </style>
  </head>
  <body>
    <main>
      <button id="target">Interaction target</button>
    </main>
    <script>
      function record(type) {
        fetch('/event?type=' + type, { cache: 'no-store' }).catch(() => {});
      }
      document.addEventListener('click', () => record('click'));
      document.addEventListener('wheel', () => record('wheel'), { passive: true });
    </script>
  </body>
</html>`;
}

function uiScript() {
  return `
on waitForProcess(processName, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      if exists process processName then return true
    end tell
    delay 0.5
  end repeat
  return false
end waitForProcess

on waitForNamedElement(processName, elementName, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      tell process processName
        if (count of windows) > 0 then
          set allItems to entire contents of window 1
        else
          set allItems to UI elements
        end if
        repeat with itemRef in allItems
          try
            if (name of itemRef as string) is elementName then return itemRef
          end try
          try
            if (value of attribute "AXIdentifier" of itemRef as string) is elementName then return itemRef
          end try
        end repeat
      end tell
    end tell
    delay 0.5
  end repeat
  error "Timed out waiting for " & elementName
end waitForNamedElement

set appName to "PlaywrightDashboard"
if not waitForProcess(appName, 30) then error "PlaywrightDashboard process did not launch"

set interactionButton to waitForNamedElement(appName, "expanded-interaction-toggle", 80)
tell application "System Events" to click interactionButton

set surface to waitForNamedElement(appName, "expanded-screenshot-surface", 80)
tell application "System Events"
  set surfacePosition to position of surface
  set surfaceSize to size of surface
end tell
set centerX to (item 1 of surfacePosition) + ((item 1 of surfaceSize) / 2)
set centerY to (item 2 of surfacePosition) + ((item 2 of surfaceSize) / 2)
return (centerX as integer) & " " & (centerY as integer)
`;
}

function uiSnapshotScript() {
  return `
set appName to "PlaywrightDashboard"
set output to ""
tell application "System Events"
  if not (exists process appName) then return "PlaywrightDashboard process is not running"
  tell process appName
    set output to output & "windows=" & (count of windows) & ", menuBars=" & (count of menu bars) & linefeed
    if (count of windows) > 0 then
      set output to output & "windowNames=" & (name of every window as string) & linefeed
      try
        set allItems to entire contents of window 1
        set output to output & "items=" & (count of allItems) & linefeed
        set limitCount to 0
        repeat with itemRef in allItems
          if limitCount > 80 then exit repeat
          set itemName to ""
          set itemRole to ""
          set itemIdentifier to ""
          try
            set itemName to name of itemRef as string
          end try
          try
            set itemRole to role of itemRef as string
          end try
          try
            set itemIdentifier to value of attribute "AXIdentifier" of itemRef as string
          end try
          if itemName is not "" or itemIdentifier is not "" then
            set output to output & itemRole & " name=" & itemName & " id=" & itemIdentifier & linefeed
            set limitCount to limitCount + 1
          end if
        end repeat
      on error errMsg
        set output to output & "snapshot-error=" & errMsg & linefeed
      end try
    end if
  end tell
end tell
return output
`;
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

function runAppleScript(script) {
  return run("osascript", ["-e", script]);
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

async function json(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} returned ${response.status}`);
  return response.json();
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
