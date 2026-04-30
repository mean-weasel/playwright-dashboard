#!/usr/bin/env node

import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  uiSnapshotScript,
  waitForAppWindowScript,
  waitForWindowScript,
  windowRectScript,
} from "./visual-snapshot/applescript.mjs";
import { startExpandedBrowserFixture } from "./visual-snapshot/browser-fixture.mjs";
import { cases, seedSessions, sessionFixture } from "./visual-snapshot/fixtures.mjs";
import { writeManifest } from "./visual-snapshot/metadata.mjs";
import {
  fsTempDir,
  run,
  runAppleScript,
  sleep,
  stopProcess,
} from "./visual-snapshot/process.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const appPath = path.join(repoRoot, "dist", "PlaywrightDashboard.app");
const artifactDir = process.env.VISUAL_SNAPSHOT_DIR
  ? path.resolve(process.env.VISUAL_SNAPSHOT_DIR)
  : path.join(repoRoot, "dist", "visual-snapshots");
const baselineDir = process.env.VISUAL_SNAPSHOT_BASELINE_DIR
  ? path.resolve(process.env.VISUAL_SNAPSHOT_BASELINE_DIR)
  : null;

await mkdir(artifactDir, { recursive: true });

for (const testCase of cases) {
  await captureCase(testCase);
}

await writeManifest({ appPath, artifactDir, baselineDir, cases });
console.log(`Visual snapshots written to ${artifactDir}`);

async function captureCase(testCase) {
  const tmpRoot = await fsTempDir(`playwright-dashboard-visual-${testCase.name}-`);
  const daemonDir = path.join(tmpRoot, "daemon");
  if (testCase.window === "expanded") {
    await captureExpandedCase(testCase, tmpRoot, daemonDir);
    return;
  }

  try {
    await seedSessions(daemonDir, testCase.sessions);
    await quitApp();

    const appArgs = [
      appPath,
      "--args",
      testCase.window === "settings" ? "--smoke-open-settings" : "--smoke-open-dashboard",
      "--smoke-daemon-dir",
      daemonDir,
      "--smoke-in-memory-store",
      "--smoke-disable-screenshots",
    ];
    if (testCase.dashboardFilter === "closed") {
      appArgs.push("--smoke-dashboard-filter-closed");
    }
    await run("open", appArgs);

    if (testCase.expectedElement) {
      await runAppleScript(waitForWindowScript(testCase.expectedElement));
    } else {
      await runAppleScript(waitForAppWindowScript());
    }
    if (testCase.afterLaunch === "closed-history") {
      await rm(daemonDir, { recursive: true, force: true });
      await mkdir(daemonDir, { recursive: true });
      await sleep(3_000);
      await runAppleScript(waitForWindowScript(testCase.finalExpectedElement));
    }
    await captureWindow(testCase.name);
  } catch (error) {
    await writeFailureArtifacts(testCase.name, error);
    throw error;
  } finally {
    await quitApp();
    await rm(tmpRoot, { recursive: true, force: true });
  }
}

async function captureExpandedCase(testCase, tmpRoot, daemonDir) {
  const sessionName = "visual-expanded";
  let fixture;

  try {
    fixture = await startExpandedBrowserFixture(tmpRoot);
    await seedSessions(daemonDir, [
      sessionFixture(sessionName, "Visual Expanded", "expanded-worktree", fixture.debugPort),
    ]);
    await quitApp();
    await run("open", [
      appPath,
      "--args",
      "--smoke-open-dashboard",
      "--smoke-daemon-dir",
      daemonDir,
      "--smoke-in-memory-store",
      "--smoke-session-id",
      sessionName,
    ]);

    await runAppleScript(waitForWindowScript(testCase.expectedElement));
    await sleep(1_500);
    await captureWindow(testCase.name);
  } catch (error) {
    await writeFailureArtifacts(testCase.name, error);
    throw error;
  } finally {
    await quitApp();
    await stopProcess(fixture?.chromeProcess);
    fixture?.server.close();
    await rm(tmpRoot, { recursive: true, force: true });
  }
}

async function captureWindow(name) {
  await runAppleScript('tell application "PlaywrightDashboard" to activate');
  const rect = parseRect(await runAppleScript(windowRectScript()));
  await captureRect(rect, path.join(artifactDir, `${name}.png`));
}

function parseRect(output) {
  const values = Object.fromEntries(
    output
      .trim()
      .split(/\s+/)
      .map((part) => part.split("="))
      .filter(([key, value]) => key && value)
      .map(([key, value]) => [key, Number(value)]),
  );
  for (const key of ["x", "y", "w", "h"]) {
    if (!Number.isFinite(values[key])) {
      throw new Error(`Invalid window rect: ${output}`);
    }
  }
  return values;
}

function captureRect(rect, outputPath) {
  const region = `${rect.x},${rect.y},${rect.w},${rect.h}`;
  return run("screencapture", ["-x", "-R", region, outputPath]);
}

async function writeFailureArtifacts(name, error) {
  await writeFile(
    path.join(artifactDir, `${name}-error.txt`),
    `${error?.stack || error?.message || String(error)}\n`,
    "utf8",
  );
  const snapshot = await runAppleScript(uiSnapshotScript()).catch((snapshotError) => {
    return `Unable to collect UI snapshot: ${snapshotError.message}`;
  });
  await writeFile(path.join(artifactDir, `${name}-ui-snapshot.txt`), snapshot, "utf8");
}

function quitApp() {
  return run("osascript", ["-e", 'tell application "PlaywrightDashboard" to quit']).catch(
    () => {},
  );
}
