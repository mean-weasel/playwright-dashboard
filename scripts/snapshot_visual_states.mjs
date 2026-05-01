#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  structuralSnapshotScript,
  uiSnapshotScript,
  waitForAppWindowScript,
  waitForWindowScript,
  windowRectScript,
} from "./visual-snapshot/applescript.mjs";
import { startExpandedBrowserFixture } from "./visual-snapshot/browser-fixture.mjs";
import { cases, seedSessions, sessionFixture } from "./visual-snapshot/fixtures.mjs";
import { writeManifest } from "./visual-snapshot/metadata.mjs";
import { runAccessibilityPreflight } from "./visual-snapshot/accessibility.mjs";
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
const structureOnly =
  process.env.VISUAL_SNAPSHOT_STRUCTURE_ONLY === "1" ||
  process.argv.includes("--structure-only");
const enforceVisualDiffs =
  process.env.VISUAL_SNAPSHOT_ENFORCE_DIFFS === "1" ||
  process.argv.includes("--enforce-visual-diffs");
const visualDiffThreshold = parseThreshold(
  process.env.VISUAL_SNAPSHOT_DIFF_THRESHOLD,
  0.01,
  "VISUAL_SNAPSHOT_DIFF_THRESHOLD",
);
const visualDiffPixelThreshold = parseWholeNumber(
  process.env.VISUAL_SNAPSHOT_PIXEL_THRESHOLD,
  2,
  "VISUAL_SNAPSHOT_PIXEL_THRESHOLD",
);
const selectedCases = filterCases(cases);

await runGuiPreflight();
await mkdir(artifactDir, { recursive: true });

for (const testCase of selectedCases) {
  await captureCase(testCase);
}

if (structureOnly) {
  await writeStructureManifest(selectedCases);
} else {
  await writeManifest({
    appPath,
    artifactDir,
    baselineDir,
    cases: selectedCases,
    enforceVisualDiffs,
    visualDiffThreshold,
    visualDiffPixelThreshold,
  });
}
console.log(`Visual snapshots written to ${artifactDir}`);

function filterCases(allCases) {
  const requested = process.env.VISUAL_SNAPSHOT_CASES
    ? process.env.VISUAL_SNAPSHOT_CASES.split(",").map((name) => name.trim()).filter(Boolean)
    : [];
  if (requested.length === 0) return allCases;

  const casesByName = new Map(allCases.map((testCase) => [testCase.name, testCase]));
  const unknown = requested.filter((name) => !casesByName.has(name));
  if (unknown.length > 0) {
    throw new Error(`Unknown visual snapshot case(s): ${unknown.join(", ")}`);
  }
  return requested.map((name) => casesByName.get(name));
}

async function runGuiPreflight() {
  try {
    await runAccessibilityPreflight({ quiet: true });
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function parseThreshold(value, fallback, label) {
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1) {
    throw new Error(`${label} must be a number from 0 to 1`);
  }
  return parsed;
}

function parseWholeNumber(value, fallback, label) {
  if (value === undefined || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 255) {
    throw new Error(`${label} must be an integer from 0 to 255`);
  }
  return parsed;
}

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
    await assertStructure(testCase);
    if (structureOnly) return;
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
    await assertStructure(testCase);
    if (structureOnly) return;
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

async function assertStructure(testCase) {
  if (!testCase.assertions) return;

  const snapshot = parseStructuralSnapshot(await runAppleScript(structuralSnapshotScript()));
  const failures = structuralFailures(snapshot, testCase.assertions);
  if (failures.length === 0) {
    await writeFile(
      path.join(artifactDir, `${testCase.name}-structure.txt`),
      structuralReport(snapshot, testCase.assertions),
      "utf8",
    );
    return;
  }

  await writeFile(
    path.join(artifactDir, `${testCase.name}-structure.txt`),
    structuralReport(snapshot, testCase.assertions, failures),
    "utf8",
  );
  throw new Error(
    [
      `Structural assertions failed for ${testCase.name}:`,
      ...failures.map((failure) => `- ${failure}`),
    ].join("\n"),
  );
}

function parseStructuralSnapshot(output) {
  const snapshot = {
    windowCount: 0,
    itemCount: 0,
    items: [],
  };
  for (const line of output.trim().split(/\r?\n/)) {
    if (line.startsWith("windowCount=")) {
      snapshot.windowCount = Number(line.slice("windowCount=".length));
      continue;
    }
    if (line.startsWith("itemCount=")) {
      snapshot.itemCount = Number(line.slice("itemCount=".length));
      continue;
    }
    if (line.startsWith("item\t")) {
      const [, role = "", name = "", identifier = ""] = line.split("\t");
      snapshot.items.push({ role, name, identifier });
    }
  }
  return snapshot;
}

function structuralFailures(snapshot, assertions) {
  const failures = [];
  const identifiers = new Set(
    snapshot.items.map((item) => item.identifier).filter(Boolean),
  );
  const names = snapshot.items.map((item) => item.name).filter(Boolean);

  if (snapshot.windowCount < 1) {
    failures.push("expected at least one app window");
  }

  for (const identifier of assertions.identifiers || []) {
    if (!identifiers.has(identifier)) {
      failures.push(`missing accessibility identifier ${identifier}`);
    }
  }

  for (const expectedName of assertions.names || []) {
    if (!names.some((name) => name.includes(expectedName))) {
      failures.push(`missing accessibility name containing ${expectedName}`);
    }
  }

  for (const [prefix, expectedCount] of Object.entries(assertions.identifierPrefixes || {})) {
    const actualCount = [...identifiers].filter((identifier) => identifier.startsWith(prefix))
      .length;
    if (actualCount !== expectedCount) {
      failures.push(
        `expected ${expectedCount} identifiers with prefix ${prefix}, found ${actualCount}`,
      );
    }
  }

  return failures;
}

function structuralReport(snapshot, assertions, failures = []) {
  const identifiers = snapshot.items
    .map((item) => item.identifier)
    .filter(Boolean)
    .sort();
  const names = snapshot.items
    .map((item) => item.name)
    .filter(Boolean)
    .sort();
  return `${JSON.stringify(
    {
      assertions,
      failures,
      windowCount: snapshot.windowCount,
      itemCount: snapshot.itemCount,
      identifiers,
      names,
    },
    null,
    2,
  )}\n`;
}

async function writeStructureManifest(testCases) {
  const snapshots = [];
  for (const testCase of testCases) {
    const filename = `${testCase.name}-structure.txt`;
    const filePath = path.join(artifactDir, filename);
    const [fileStat, content] = await Promise.all([stat(filePath), readFile(filePath)]);
    snapshots.push({
      name: testCase.name,
      filename,
      window: testCase.window,
      bytes: fileStat.size,
      sha256: createHash("sha256").update(content).digest("hex"),
      baseline: { status: "not-applicable" },
    });
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    mode: "structure-only",
    structuralAssertions: "blocking",
    appPath,
    baselineDir: null,
    snapshots,
  };
  await writeFile(
    path.join(artifactDir, "manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8",
  );
  await writeFile(path.join(artifactDir, "summary.md"), `${structureSummary(manifest)}\n`, "utf8");
}

function structureSummary(manifest) {
  const lines = [
    "## Visual Structure Smoke",
    "",
    `Mode: \`${manifest.mode}\``,
    `Structural assertions: \`${manifest.structuralAssertions}\``,
    `Generated: \`${manifest.generatedAt}\``,
    "",
    "| Snapshot | Window | Bytes | Baseline |",
    "| --- | --- | ---: | --- |",
  ];

  for (const snapshot of manifest.snapshots) {
    lines.push(
      `| \`${snapshot.filename}\` | ${snapshot.window} | ${snapshot.bytes} | not applicable |`,
    );
  }

  return lines.join("\n");
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
