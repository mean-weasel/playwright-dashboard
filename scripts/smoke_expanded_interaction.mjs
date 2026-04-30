#!/usr/bin/env node

import { execFile, spawn } from "node:child_process";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
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
const forceSnapshotFallback = process.env.SMOKE_FORCE_SNAPSHOT_FALLBACK === "1";
const sessionName = `smoke-interaction-${process.pid}`;
const displayName = "Smoke Interaction";
const tmpRoot = await fsTempDir("playwright-dashboard-expanded-smoke-");
const firstSurfaceShot = path.join(tmpRoot, "surface-before.png");
const secondSurfaceShot = path.join(tmpRoot, "surface-after.png");
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
const events = [];
const accessibilityHelp = [
  "macOS denied assistive access for the process running this smoke test.",
  "Grant Accessibility access to every process identity in the launch chain: terminal/editor, Node.js, osascript, and any wrapper/helper.",
  `Node.js binary: ${process.execPath}`,
  "osascript binary: /usr/bin/osascript",
  "System Settings > Privacy & Security > Accessibility",
  "After changing Accessibility settings, quit and reopen the terminal/editor before rerunning QA.",
].join("\n");

try {
  // Kill any leftover instance so `open --args` delivers fresh launch arguments.
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);

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

  const appArgs = [
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-session-id",
    sessionName,
  ];
  if (forceSnapshotFallback) {
    appArgs.push("--smoke-force-snapshot-fallback");
  }
  await run("open", appArgs);
  appOpened = true;
  let uiResult;
  try {
    uiResult = await runAppleScript(uiScript());
  } catch (error) {
    const snapshot = await runAppleScript(uiSnapshotScript()).catch((snapshotError) => {
      return `Unable to collect UI snapshot: ${snapshotError.message}`;
    });
    console.error(snapshot);
    throw error;
  }
  const points = parseUIScriptResult(uiResult);
  if (!forceSnapshotFallback) {
    await assertSurfacePixelsChange(points.initialRect, firstSurfaceShot, secondSurfaceShot);
  }

  await postPointerSequence(points.initialX, points.initialY);

  await waitFor(() => {
    const types = new Set(events.map((event) => event.type));
    return types.has("click") && types.has("wheel");
  }, "page click and wheel events");

  const resizedPoints = parseResizeScriptResult(await runAppleScript(resizeScript()));
  await postPointerSequence(resizedPoints.x, resizedPoints.y);

  await waitFor(() => {
    return events.filter((event) => event.type === "click").length >= 2;
  }, "page click after window resize");

  await runAppleScript(typingScript());

  await waitFor(() => {
    return events.some((event) => event.type === "input" && event.value === "ab");
  }, "typed input and backspace");
  await waitFor(() => {
    return events.some((event) => event.type === "keydown" && event.key === "Enter");
  }, "enter key event");

  console.log("Expanded interaction smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error, events);
  throw error;
} finally {
  if (appOpened) {
    await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(
      () => {},
    );
  }
  await stopChrome();
  server?.close();
  await rm(daemonDir, { recursive: true, force: true });
  await rm(tmpRoot, { recursive: true, force: true });
}

function activateApp() {
  return run("osascript", [
    "-e",
    'tell application "PlaywrightDashboard" to activate',
    "-e",
    'tell application "System Events" to set frontmost of process "PlaywrightDashboard" to true',
  ]);
}

async function postPointerSequence(x, y) {
  await activateApp();
  await sleep(500);
  const helper = path.join(repoRoot, "scripts", "post_pointer_events.swift");
  await run(helper, [String(x), String(y)]);
  await sleep(250);
  await run(helper, [String(x), String(y)]);
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

async function writeSmokeArtifacts(error, events) {
  if (!artifactDir) return;
  await mkdir(artifactDir, { recursive: true });
  await writeFile(
    path.join(artifactDir, "error.txt"),
    `${error?.stack || error?.message || String(error)}\n`,
    "utf8",
  );
  await writeFile(path.join(artifactDir, "events.json"), `${JSON.stringify(events, null, 2)}\n`);

  const snapshot = await runAppleScript(uiSnapshotScript()).catch((snapshotError) => {
    return `Unable to collect UI snapshot: ${snapshotError.message}`;
  });
  await writeFile(path.join(artifactDir, "ui-snapshot.txt"), snapshot, "utf8");

  await copyIfPresent(firstSurfaceShot, path.join(artifactDir, "surface-before.png"));
  await copyIfPresent(secondSurfaceShot, path.join(artifactDir, "surface-after.png"));
}

async function copyIfPresent(source, destination) {
  try {
    await copyFile(source, destination);
  } catch {}
}

function parseUIScriptResult(output) {
  const values = Object.fromEntries(
    output
      .trim()
      .split(/\s+/)
      .map((part) => part.split("="))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, Number(value)]),
  );
  const required = ["initialX", "initialY", "initialW", "initialH"];
  for (const key of required) {
    if (!Number.isFinite(values[key])) {
      throw new Error(`Invalid UI script result, missing ${key}: ${output}`);
    }
  }
  values.initialRect = {
    x: values.initialX - Math.floor(values.initialW / 2),
    y: values.initialY - Math.floor(values.initialH / 2),
    width: values.initialW,
    height: values.initialH,
  };
  return values;
}

function parseResizeScriptResult(output) {
  const values = Object.fromEntries(
    output
      .trim()
      .split(/\s+/)
      .map((part) => part.split("="))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, Number(value)]),
  );
  if (!Number.isFinite(values.x) || !Number.isFinite(values.y)) {
    throw new Error(`Invalid resize script result: ${output}`);
  }
  return values;
}

async function assertSurfacePixelsChange(rect, beforePath, afterPath) {
  await captureRect(rect, beforePath);
  await sleep(1_500);
  await captureRect(rect, afterPath);

  const [before, after] = await Promise.all([readFile(beforePath), readFile(afterPath)]);
  if (before.equals(after)) {
    const snapshot = await runAppleScript(uiSnapshotScript()).catch((snapshotError) => {
      return `Unable to collect UI snapshot: ${snapshotError.message}`;
    });
    throw new Error(
      `Expected expanded screenshot surface pixels to change under live screencast\n${snapshot}`,
    );
  }
}

function captureRect(rect, outputPath) {
  const region = `${Math.round(rect.x)},${Math.round(rect.y)},${Math.round(rect.width)},${Math.round(rect.height)}`;
  return run("screencapture", ["-x", "-R", region, outputPath]);
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
        events.push({
          type: url.searchParams.get("type"),
          key: url.searchParams.get("key"),
          value: url.searchParams.get("value"),
          at: Date.now(),
        });
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
      input {
        position: fixed;
        left: 50%;
        top: 50%;
        transform: translate(-50%, -50%);
        font-size: 24px;
        padding: 16px;
        width: 360px;
      }
      output { display: block; margin-bottom: 24px; font-size: 32px; font-variant-numeric: tabular-nums; }
    </style>
  </head>
  <body>
    <main>
      <output id="counter" aria-label="Counter">0</output>
      <button id="target">Interaction target</button>
      <input id="text-target" aria-label="Text target" autocomplete="off" autofocus />
    </main>
    <script>
      const counter = document.getElementById('counter');
      const input = document.getElementById('text-target');
      let value = 0;
      setInterval(() => {
        value += 1;
        counter.textContent = String(value);
      }, 250);
      function record(type, params = {}) {
        const url = new URL('/event', location.href);
        url.searchParams.set('type', type);
        for (const [key, value] of Object.entries(params)) {
          url.searchParams.set(key, value);
        }
        fetch(url, { cache: 'no-store' }).catch(() => {});
      }
      document.addEventListener('click', () => {
        input.focus();
        record('click');
      });
      document.addEventListener('wheel', () => record('wheel'), { passive: true });
      document.addEventListener('keydown', (event) => record('keydown', { key: event.key }));
      input.addEventListener('input', () => record('input', { value: input.value }));
      input.focus();
    </script>
  </body>
</html>`;
}

function uiScript() {
  return `
set expectedRefreshBadge to "${forceSnapshotFallback ? "Snapshot fallback" : "Live screencast"}"

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

on waitForNamedElementValue(processName, elementName, expectedValue, maxAttempts)
  repeat with attempt from 1 to maxAttempts
    tell application "System Events"
      tell process processName
        set allItems to entire contents of window 1
        repeat with itemRef in allItems
          try
            if (name of itemRef as string) is elementName then
              try
                if (value of itemRef as string) is expectedValue then return true
              end try
            end if
          end try
        end repeat
      end tell
    end tell
    delay 0.5
  end repeat
  return false
end waitForNamedElementValue

set appName to "PlaywrightDashboard"
if not waitForProcess(appName, 30) then error "PlaywrightDashboard process did not launch"

set refreshBadge to waitForNamedElement(appName, expectedRefreshBadge, 80)

set interactionButton to waitForNamedElement(appName, "expanded-interaction-toggle", 80)
tell application "System Events" to click interactionButton

set surface to waitForNamedElement(appName, "expanded-screenshot-surface", 80)
tell application "System Events"
  set surfacePosition to position of surface
  set surfaceSize to size of surface
end tell
set centerX to (item 1 of surfacePosition) + ((item 1 of surfaceSize) / 2)
set centerY to (item 2 of surfacePosition) + ((item 2 of surfaceSize) / 2)
set initialWidth to (item 1 of surfaceSize) as integer
set initialHeight to (item 2 of surfaceSize) as integer

return "initialX=" & (centerX as integer) & " initialY=" & (centerY as integer) & " initialW=" & initialWidth & " initialH=" & initialHeight
`;
}

function resizeScript() {
  return `
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
tell application "System Events"
  tell process appName
    set size of window 1 to {900, 620}
  end tell
end tell
delay 1

set surface to waitForNamedElement(appName, "expanded-screenshot-surface", 80)
tell application "System Events"
  set resizedSurfacePosition to position of surface
  set resizedSurfaceSize to size of surface
end tell
set resizedCenterX to (item 1 of resizedSurfacePosition) + ((item 1 of resizedSurfaceSize) / 2)
set resizedCenterY to (item 2 of resizedSurfacePosition) + ((item 2 of resizedSurfaceSize) / 2)

return "x=" & (resizedCenterX as integer) & " y=" & (resizedCenterY as integer)
`;
}

function typingScript() {
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

-- Click the screenshot surface to ensure PointerCaptureView is first responder.
-- Screenshot polling re-renders can displace it between the previous click and typing.
set surface to waitForNamedElement(appName, "expanded-screenshot-surface", 10)
tell application "System Events"
  tell process appName
    set frontmost to true
  end tell
  click surface
  delay 0.5
  keystroke "abc"
  delay 0.2
  key code 51
  delay 0.2
  key code 36
end tell
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
        const output = stderr || stdout || error.message;
        const message = isAccessibilityDenied(output)
          ? `${accessibilityHelp}\n\n${output}`
          : `${command} failed: ${output}`;
        reject(new Error(message));
        return;
      }
      resolve(stdout);
    });
  });
}

function runAppleScript(script) {
  return run("osascript", ["-e", script]);
}

function isAccessibilityDenied(output) {
  return output.includes("-25211") || output.includes("not allowed assistive access");
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
