#!/usr/bin/env node

import { execFile, spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
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
const chromePath =
  process.env.CHROME_PATH ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const accessibilityHelp = staticAccessibilityHelp();
const tmpRoot = await fsTempDir("playwright-dashboard-multi-smoke-");
const daemonRoot = path.join(tmpRoot, "daemon");
const smokeId = String(process.pid);
const specs = ["alpha", "bravo", "charlie"].map((slug, index) => ({
  slug,
  index,
  sessionId: `multi-${slug}-${smokeId}`,
  label: `Multi ${titleCase(slug)}`,
  workspaceHash: `multi-${slug}-hash`,
  workspaceDir: path.join(tmpRoot, "workspaces", `multi-${slug}`),
  debugPort: 0,
  server: null,
  chromeProcess: null,
  events: [],
}));

let appOpened = false;

await runGuiPreflight();

try {
  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);

  for (const spec of specs) {
    spec.server = await startSessionServer(spec);
    spec.debugPort = await freePort();
    spec.chromeProcess = spawn(chromePath, [
      `--user-data-dir=${path.join(tmpRoot, `${spec.slug}-chrome-profile`)}`,
      `--remote-debugging-port=${spec.debugPort}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
      spec.server.rootURL,
    ], { stdio: "ignore" });
    await waitFor(async () => {
      const pages = await json(`http://127.0.0.1:${spec.debugPort}/json/list`).catch(() => []);
      return pages.some((page) => page.url === spec.server.rootURL);
    }, `${spec.label} Chrome CDP page`);
    await createSessionFile(spec);
  }

  await run("defaults", [
    "write",
    "com.neonwatty.PlaywrightDashboard",
    "expandedInteractionEnabled",
    "-bool",
    "false",
  ]);

  await launchApp();
  await runAppleScript(waitForDashboardCardsScript(specs));
  await quitApp();

  for (const spec of specs) {
    await launchApp(spec.sessionId);
    await runAppleScript(waitForExpandedSessionScript());
    await waitFor(async () => {
      const pages = await json(`http://127.0.0.1:${spec.debugPort}/json/list`);
      return pages.some((page) => page.url === spec.server.rootURL);
    }, `${spec.label} root page remains selected`);
    await quitApp();
  }

  const controlled = specs[0];
  const untouched = specs.slice(1);
  await launchApp(controlled.sessionId);
  const surface = parsePointResult(await runAppleScript(waitForExpandedSessionScript()));
  await runAppleScript(enableControlModeScript());
  await runAppleScript(navigateScript(controlled.server.nextURL));
  await waitForEvent(controlled, (event) => event.path === "/next", `${controlled.label} /next`);
  await waitFor(async () => {
    const pages = await json(`http://127.0.0.1:${controlled.debugPort}/json/list`);
    return pages.some((page) => page.url === controlled.server.nextURL);
  }, `${controlled.label} CDP URL update`);

  await postPointerSequence(surface.x, surface.y);
  await waitForEvent(
    controlled,
    (event) => event.type === "click" || event.type === "wheel",
    `${controlled.label} input event`,
  );

  for (const spec of untouched) {
    if (spec.events.some((event) => event.path === "/next")) {
      throw new Error(`${spec.label} unexpectedly received navigation to /next`);
    }
    if (spec.events.some((event) => event.type === "click" || event.type === "wheel")) {
      throw new Error(`${spec.label} unexpectedly received forwarded input`);
    }
  }

  console.log("Multi-session smoke passed");
} catch (error) {
  await writeSmokeArtifacts(error);
  throw error;
} finally {
  await quitApp();
  for (const spec of specs) {
    await stopChrome(spec);
    spec.server?.close();
  }
  await rm(tmpRoot, { recursive: true, force: true });
}

async function launchApp(selectedSessionId = null) {
  const appArgs = [
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-in-memory-store",
    "--smoke-disable-safe-mode",
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
  await sleep(1_000);
}

async function createSessionFile(spec) {
  const sessionDir = path.join(daemonRoot, spec.workspaceHash);
  await mkdir(sessionDir, { recursive: true });
  await mkdir(spec.workspaceDir, { recursive: true });
  const session = {
    name: spec.sessionId,
    version: "1",
    timestamp: Date.now() + spec.index,
    socketPath: path.join(tmpRoot, `${spec.slug}.sock`),
    workspaceDir: spec.workspaceDir,
    cli: {},
    browser: {
      browserName: "chromium",
      launchOptions: {
        headless: false,
        chromiumSandbox: false,
        cdpPort: spec.debugPort,
      },
    },
  };
  await writeFile(
    path.join(sessionDir, `${spec.sessionId}.session`),
    `${JSON.stringify(session)}\n`,
    "utf8",
  );
}

function startSessionServer(spec) {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      const url = new URL(request.url, "http://127.0.0.1");
      if (url.pathname === "/event") {
        spec.events.push({
          type: url.searchParams.get("type"),
          key: url.searchParams.get("key"),
          value: url.searchParams.get("value"),
          path: url.searchParams.get("path"),
          at: Date.now(),
        });
        response.writeHead(204);
        response.end();
        return;
      }
      if (url.pathname === "/events.json") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify(spec.events));
        return;
      }
      spec.events.push({ type: "request", path: url.pathname, at: Date.now() });
      response.writeHead(200, { "content-type": "text/html" });
      response.end(testPage(spec, url.pathname));
    });
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      resolve({
        port,
        rootURL: `http://127.0.0.1:${port}/`,
        nextURL: `http://127.0.0.1:${port}/next`,
        close: () => server.close(),
      });
    });
  });
}

function testPage(spec, routePath) {
  const title = routePath === "/next" ? `${spec.label} Next` : spec.label;
  return `<!doctype html>
<html>
  <head>
    <title>${title}</title>
    <style>
      body { margin: 0; font: 16px -apple-system, BlinkMacSystemFont, sans-serif; }
      main { min-height: 180vh; padding: 72px; background: hsl(${spec.index * 85}, 70%, 94%); }
      h1 { font-size: 42px; margin: 0 0 24px; }
      input { font-size: 22px; padding: 14px; width: 340px; }
    </style>
  </head>
  <body>
    <main>
      <h1>${title}</h1>
      <input id="text-target" aria-label="Text target" autocomplete="off" autofocus />
    </main>
    <script>
      const input = document.getElementById('text-target');
      function record(type, params = {}) {
        const url = new URL('/event', location.href);
        url.searchParams.set('type', type);
        url.searchParams.set('path', location.pathname);
        for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
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

function waitForDashboardCardsScript(sessionSpecs) {
  const waits = sessionSpecs
    .map((spec) => `set card_${spec.slug} to waitForNamedElement(appName, "session-card-${spec.sessionId}", 80)`)
    .join("\n");
  return `${appleScriptHelpers()}
set appName to "PlaywrightDashboard"
if not waitForProcess(appName, 30) then error "PlaywrightDashboard process did not launch"
${waits}
return "cards=${sessionSpecs.length}"
`;
}

function waitForExpandedSessionScript() {
  return `${appleScriptHelpers()}
set appName to "PlaywrightDashboard"
if not waitForProcess(appName, 30) then error "PlaywrightDashboard process did not launch"
set surface to waitForNamedElement(appName, "expanded-screenshot-surface", 80)
set navField to waitForNamedElement(appName, "expanded-navigate-url-field", 80)
tell application "System Events"
  set surfacePosition to position of surface
  set surfaceSize to size of surface
end tell
set centerX to (item 1 of surfacePosition) + ((item 1 of surfaceSize) / 2)
set centerY to (item 2 of surfacePosition) + ((item 2 of surfaceSize) / 2)
return "x=" & (centerX as integer) & " y=" & (centerY as integer)
`;
}

function enableControlModeScript() {
  return `${appleScriptHelpers()}
set appName to "PlaywrightDashboard"
set interactionMode to waitForNamedElement(appName, "expanded-interaction-mode", 80)
set controlButton to waitForFirstNamedElement(appName, "Control", "cursorarrow.click.2", 80)
tell application "System Events" to click controlButton
set interactionBadge to waitForNamedElement(appName, "Control mode", 40)
`;
}

function navigateScript(url) {
  return `${appleScriptHelpers()}
set appName to "PlaywrightDashboard"
set navField to waitForNamedElement(appName, "expanded-navigate-url-field", 80)
set navButton to waitForNamedElement(appName, "expanded-navigate-url-button", 80)
tell application "PlaywrightDashboard" to activate
tell application "System Events"
  tell process appName
    set frontmost to true
  end tell
  click navField
  try
    set focused of navField to true
  end try
  delay 0.2
  keystroke "a" using command down
  delay 0.1
  set the clipboard to "${escapeAppleScriptString(url)}"
  keystroke "v" using command down
  delay 0.5
  click navButton
end tell
`;
}

function appleScriptHelpers() {
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

on waitForFirstNamedElement(processName, firstElementName, secondElementName, maxAttempts)
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
            set itemName to name of itemRef as string
            if itemName is firstElementName or itemName is secondElementName then return itemRef
          end try
          try
            set itemIdentifier to value of attribute "AXIdentifier" of itemRef as string
            if itemIdentifier is firstElementName or itemIdentifier is secondElementName then return itemRef
          end try
        end repeat
      end tell
    end tell
    delay 0.5
  end repeat
  error "Timed out waiting for " & firstElementName & " or " & secondElementName
end waitForFirstNamedElement
`;
}

async function postPointerSequence(x, y) {
  await activateApp();
  await sleep(500);
  const helper = path.join(repoRoot, "scripts", "post_pointer_events.swift");
  await run(helper, [String(x), String(y)]);
  await sleep(250);
  await run(helper, [String(x), String(y)]);
}

function parsePointResult(output) {
  const values = Object.fromEntries(
    output
      .trim()
      .split(/\s+/)
      .map((part) => part.split("="))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, Number(value)]),
  );
  if (!Number.isFinite(values.x) || !Number.isFinite(values.y)) {
    throw new Error(`Invalid point output: ${output}`);
  }
  return values;
}

async function waitForEvent(spec, predicate, label) {
  await waitFor(() => predicate(spec.events.at(-1)) || spec.events.some(predicate), label);
}

async function activateApp() {
  await run("osascript", [
    "-e",
    'tell application "PlaywrightDashboard" to activate',
    "-e",
    'tell application "System Events" to set frontmost of process "PlaywrightDashboard" to true',
  ]);
}

async function runGuiPreflight() {
  try {
    await runAccessibilityPreflight({ quiet: true });
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

async function stopChrome(spec) {
  if (!spec.chromeProcess || spec.chromeProcess.exitCode !== null) return;
  spec.chromeProcess.kill("SIGTERM");
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 2_000);
    spec.chromeProcess.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

async function writeSmokeArtifacts(error) {
  if (!artifactDir) return;
  await mkdir(artifactDir, { recursive: true });
  await writeFile(
    path.join(artifactDir, "error.txt"),
    `${error?.stack || error?.message || String(error)}\n`,
    "utf8",
  );
  await writeFile(path.join(artifactDir, "events.json"), `${JSON.stringify(specs, eventReplacer, 2)}\n`);
  const snapshot = await runAppleScript(uiSnapshotScript()).catch(
    (snapshotError) => `Unable to collect UI snapshot: ${snapshotError.message}`,
  );
  await writeFile(path.join(artifactDir, "ui-snapshot.txt"), snapshot, "utf8");
}

function uiSnapshotScript() {
  return `${appleScriptHelpers()}
set appName to "PlaywrightDashboard"
set output to ""
tell application "System Events"
  if not (exists process appName) then return "PlaywrightDashboard process is not running"
  tell process appName
    set output to output & "windows=" & (count of windows) & linefeed
    if (count of windows) > 0 then
      set output to output & "windowNames=" & (name of every window as string) & linefeed
      try
        set allItems to entire contents of window 1
        set output to output & "items=" & (count of allItems) & linefeed
        set limitCount to 0
        repeat with itemRef in allItems
          if limitCount > 120 then exit repeat
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
    execFile(
      command,
      args,
      { cwd: repoRoot, maxBuffer: 10 * 1024 * 1024, ...options },
      (error, stdout, stderr) => {
        if (error) {
          const output = stderr || stdout || error.message;
          const message = isAccessibilityDenied(output)
            ? `${accessibilityHelp}\n\n${output}`
            : `${command} failed: ${output}`;
          reject(new Error(message));
          return;
        }
        resolve(stdout);
      },
    );
  });
}

function runAppleScript(script) {
  return run("osascript", ["-e", script], { timeout: 120_000 });
}

async function waitFor(predicate, label, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await sleep(500);
  }
  throw new Error(`Timed out waiting for ${label}`);
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

async function json(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} returned ${response.status}`);
  return response.json();
}

async function fsTempDir(prefix) {
  const { mkdtemp } = await import("node:fs/promises");
  return mkdtemp(path.join(os.tmpdir(), prefix));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function titleCase(value) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function escapeAppleScriptString(value) {
  return value.replaceAll("\\", "\\\\").replaceAll("\"", "\\\"");
}

function eventReplacer(key, value) {
  if (key === "server" || key === "chromeProcess") return undefined;
  return value;
}
