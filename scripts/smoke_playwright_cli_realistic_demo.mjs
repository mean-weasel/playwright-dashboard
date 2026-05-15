#!/usr/bin/env node

import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readdir, readFile, realpath, rm, stat, writeFile } from "node:fs/promises";
import { createReadStream } from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { runAccessibilityPreflight } from "./visual-snapshot/accessibility.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const fixtureDir = path.join(repoRoot, "fixtures", "e2e-apps", "operator-workbench");
const dryRun = process.argv.includes("--dry-run") || process.env.REALISTIC_E2E_DRY_RUN === "1";
const artifactDir = process.env.SMOKE_ARTIFACT_DIR
  ? path.resolve(process.env.SMOKE_ARTIFACT_DIR)
  : path.join(repoRoot, "dist", dryRun ? "realistic-e2e-dry-run" : "realistic-e2e-artifacts");
const playwrightCLI = await resolveExecutable("playwright-cli", [
  "/opt/homebrew/bin/playwright-cli",
  "/usr/local/bin/playwright-cli",
]);
const playwrightCLIScript = await realpath(playwrightCLI).catch(() => playwrightCLI);
const tmpRoot = await mkdtemp(path.join(os.tmpdir(), "playwright-dashboard-realistic-e2e-"));
const daemonRoot = path.join(tmpRoot, "daemon");
const readinessRoot = path.join(tmpRoot, "readiness");
const workspaceDir = path.join(tmpRoot, "workspace");
const cliEnv = {
  ...process.env,
  PATH: [
    path.dirname(process.execPath),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    process.env.PATH ?? "",
  ].filter(Boolean).join(path.delimiter),
  PLAYWRIGHT_DAEMON_SESSION_DIR: daemonRoot,
  PWTEST_CLI_GLOBAL_CONFIG: path.join(tmpRoot, "no-global-config"),
};
const smokeId = String(process.pid);
const spec = {
  sessionId: `realistic-${smokeId}`,
  label: "Operator Workbench",
  debugPort: 0,
  sessionFile: null,
  server: null,
};
const progress = [];

try {
  await rm(artifactDir, { recursive: true, force: true });
  await mkdir(artifactDir, { recursive: true });
  await validateFixture();

  if (dryRun) {
    logProgress("Dry-run validated Operator Workbench fixture and smoke prerequisites");
    await writeJson("dry-run.json", {
      fixtureDir,
      artifactDir,
      expectedNormalCommand: "RUN_REALISTIC_E2E_SMOKE=1 make smoke-realistic-e2e",
      expectedDryRunCommand: "REALISTIC_E2E_DRY_RUN=1 make smoke-realistic-e2e",
      requiredTools: ["playwright-cli", "Google Chrome", "Accessibility permission"],
    });
    console.log("Realistic E2E dry-run passed");
    process.exit(0);
  }

  await assertPackagedApp();
  await runAccessibilityPreflight({ quiet: true });
  await mkdir(path.join(workspaceDir, ".playwright"), { recursive: true });
  await ensurePlaywrightCLI();

  spec.server = await startFixtureServer();
  logProgress(`Fixture server listening at ${spec.server.rootURL}`);

  await run("pkill", ["-x", "PlaywrightDashboard"]).catch(() => {});
  await sleep(1_000);

  logProgress(`Opening Playwright CLI session ${spec.sessionId}`);
  await openPlaywrightSession(spec, spec.server.rootURL);
  await loadRealSessionFile(spec);
  await waitForCDPURL(spec, spec.server.rootURL, "fixture root page");

  logProgress("Launching Playwright Dashboard expanded view in Safe mode");
  const readinessDir = path.join(readinessRoot, "expanded");
  await launchApp(readinessDir);
  const readiness = await waitForExpandedReadiness(readinessDir, {
    sessionId: spec.sessionId,
    safeMode: true,
    navigationEnabled: false,
  });
  await writeJson("expanded-ready.json", readiness);

  logProgress("Capturing Dashboard UI artifacts");
  await writeText("ui-snapshot.txt", await uiSnapshot());
  await captureDashboardWindow("dashboard-window.png");

  const incidentURL = `${spec.server.rootURL}#incident-alpha`;
  const runbookURL = `${spec.server.rootURL}#runbook`;
  logProgress("Driving fixture hash navigation through playwright-cli");
  await runPlaywrightCLI([`-s=${spec.sessionId}`, "goto", incidentURL], { cwd: workspaceDir });
  await waitForCDPURL(spec, incidentURL, "incident route");
  await runPlaywrightCLI([`-s=${spec.sessionId}`, "goto", runbookURL], { cwd: workspaceDir });
  await waitForCDPURL(spec, runbookURL, "runbook route");

  await writeJson("scenario.json", {
    sessionId: spec.sessionId,
    rootURL: spec.server.rootURL,
    incidentURL,
    runbookURL,
    debugPort: spec.debugPort,
    artifacts: ["progress.log", "expanded-ready.json", "ui-snapshot.txt", "dashboard-window.png"],
  });
  logProgress("Realistic E2E/demo smoke assertions passed");
  console.log(`Realistic E2E/demo smoke passed. Artifacts: ${artifactDir}`);
} catch (error) {
  await writeFailureArtifacts(error);
  throw error;
} finally {
  await writeText("progress.log", `${progress.join("\n")}\n`).catch(() => {});
  await run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(() => {});
  await closePlaywrightSession(spec);
  spec.server?.close();
  await rm(tmpRoot, { recursive: true, force: true });
}

async function validateFixture() {
  const required = ["index.html", "styles.css", "app.js", "README.md"];
  for (const filename of required) {
    const file = path.join(fixtureDir, filename);
    const fileStat = await stat(file);
    if (fileStat.size <= 0) throw new Error(`Fixture file is empty: ${file}`);
  }
  const html = await readFile(path.join(fixtureDir, "index.html"), "utf8");
  const selectors = [
    "data-route=\"queue\"",
    "data-route=\"incident-alpha\"",
    "data-route=\"runbook\"",
    "review-dialog",
    "escalation-form",
    "scroll-lab",
    "pulse-output",
  ];
  for (const selector of selectors) {
    if (!html.includes(selector)) throw new Error(`Fixture is missing ${selector}`);
  }
}

async function assertPackagedApp() {
  const executable = path.join(appPath, "Contents", "MacOS", "PlaywrightDashboard");
  const fileStat = await stat(executable).catch(() => null);
  if (!fileStat || (fileStat.mode & 0o111) === 0) {
    throw new Error(`Packaged app is missing. Run make validate-package first: ${executable}`);
  }
}

async function ensurePlaywrightCLI() {
  await runPlaywrightCLI(["--version"], { cwd: workspaceDir });
}

async function resolveExecutable(command, fallbackPaths) {
  if (process.env.PLAYWRIGHT_CLI_PATH) return process.env.PLAYWRIGHT_CLI_PATH;
  for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
    if (!directory) continue;
    const candidate = path.join(directory, command);
    if (await isExecutable(candidate)) return candidate;
  }
  for (const candidate of fallbackPaths) {
    if (await isExecutable(candidate)) return candidate;
  }
  return command;
}

async function isExecutable(candidate) {
  try {
    const fileStat = await stat(candidate);
    return fileStat.isFile() && (fileStat.mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

function startFixtureServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer(async (request, response) => {
      const requestURL = new URL(request.url, "http://127.0.0.1");
      const pathname = requestURL.pathname === "/" ? "/index.html" : requestURL.pathname;
      const safePath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, "");
      const filePath = path.join(fixtureDir, safePath);
      if (!filePath.startsWith(fixtureDir)) {
        response.writeHead(403);
        response.end();
        return;
      }
      const fileStat = await stat(filePath).catch(() => null);
      if (!fileStat || !fileStat.isFile()) {
        response.writeHead(404);
        response.end("Not found");
        return;
      }
      const contentType = contentTypeFor(filePath);
      const stream = createReadStream(filePath);
      response.writeHead(200, { "content-type": contentType });
      stream.pipe(response);
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

function contentTypeFor(filePath) {
  if (filePath.endsWith(".html")) return "text/html";
  if (filePath.endsWith(".css")) return "text/css";
  if (filePath.endsWith(".js")) return "text/javascript";
  return "application/octet-stream";
}

async function openPlaywrightSession(s, url) {
  await runPlaywrightCLI(
    [`-s=${s.sessionId}`, "open", url, "--browser=chrome", "--headed"],
    { cwd: workspaceDir, timeout: 120_000 },
  );
}

async function closePlaywrightSession(s) {
  if (!s.sessionId) return;
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

async function waitForCDPURL(s, expectedURL, label) {
  await waitFor(async () => {
    const pages = await json(`http://127.0.0.1:${s.debugPort}/json/list`).catch(() => []);
    return pages.some((page) => page.type === "page" && page.url === expectedURL);
  }, `CDP URL for ${label}`, 45_000);
}

async function launchApp(readinessDir) {
  await rm(readinessDir, { recursive: true, force: true });
  await mkdir(readinessDir, { recursive: true });
  await run("open", [
    "-n",
    appPath,
    "--args",
    "--smoke-open-dashboard",
    "--smoke-daemon-dir",
    daemonRoot,
    "--smoke-in-memory-store",
    "--smoke-safe-mode",
    "--smoke-session-id",
    spec.sessionId,
    "--smoke-readiness-dir",
    readinessDir,
  ]);
}

async function waitForExpandedReadiness(readinessDir, expectations) {
  const filePath = path.join(readinessDir, "expanded-ready.json");
  await waitFor(async () => {
    const payload = await readJSONFile(filePath).catch(() => null);
    if (!payload) return false;
    if (payload.session?.sessionId !== expectations.sessionId) return false;
    if (payload.safeMode !== expectations.safeMode) return false;
    if (payload.navigationEnabled !== expectations.navigationEnabled) return false;
    return true;
  }, "expanded readiness", 90_000);
  return readJSONFile(filePath);
}

async function uiSnapshot() {
  return runAppleScript(`
set appName to "PlaywrightDashboard"
tell application "System Events"
  if not (exists process appName) then return "PlaywrightDashboard process is not running"
  tell process appName
    set output to "windowCount=" & (count of windows) & linefeed
    if (count of windows) > 0 then
      set allItems to entire contents of window 1
      repeat with itemRef in allItems
        set roleText to ""
        set nameText to ""
        set idText to ""
        try
          set roleText to role of itemRef as string
        end try
        try
          set nameText to name of itemRef as string
        end try
        try
          set idText to value of attribute "AXIdentifier" of itemRef as string
        end try
        if roleText is not "" or nameText is not "" or idText is not "" then
          set output to output & roleText & tab & nameText & tab & idText & linefeed
        end if
      end repeat
    end if
  end tell
end tell
return output
`);
}

async function captureDashboardWindow(filename) {
  const rect = await runAppleScript(`
set appName to "PlaywrightDashboard"
tell application "System Events"
  tell process appName
    if (count of windows) = 0 then error "No PlaywrightDashboard window"
    set pos to position of window 1
    set sz to size of window 1
    set rectX to item 1 of pos as integer
    set rectY to item 2 of pos as integer
    set rectW to item 1 of sz as integer
    set rectH to item 2 of sz as integer
    return (rectX as string) & "," & (rectY as string) & "," & (rectW as string) & "," & (rectH as string)
  end tell
end tell
`);
  const cleanRect = rect.trim().replaceAll(" ", "");
  await run("screencapture", ["-x", `-R${cleanRect}`, path.join(artifactDir, filename)]);
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
        resolve(stdout.trim());
      },
    );
  });
}

function runPlaywrightCLI(args, options = {}) {
  if (playwrightCLIScript.endsWith(".js")) {
    return run(process.execPath, [playwrightCLIScript, ...args], { env: cliEnv, ...options });
  }
  return run(playwrightCLI, args, { env: cliEnv, ...options });
}

function runAppleScript(source) {
  return run("osascript", ["-e", source], { timeout: 90_000 });
}

async function json(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (response) => {
        let data = "";
        response.setEncoding("utf8");
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

async function readJSONFile(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function writeJson(filename, value) {
  await writeFile(path.join(artifactDir, filename), `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function writeText(filename, value) {
  await writeFile(path.join(artifactDir, filename), value, "utf8");
}

async function writeFailureArtifacts(error) {
  await writeJson("error.json", {
    error: String(error?.stack ?? error),
    progress,
  }).catch(() => {});
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function logProgress(message) {
  const stamped = `[${new Date().toISOString()}] ${message}`;
  console.log(stamped);
  progress.push(stamped);
}
