#!/usr/bin/env node

import { execFile } from "node:child_process";
import path from "node:path";

const appPath = process.argv[2];
if (!appPath) {
  throw new Error("Usage: smoke_release_launch.mjs /path/to/PlaywrightDashboard.app");
}

const resolvedAppPath = path.resolve(appPath);
const processName = "PlaywrightDashboard";

try {
  await run("pkill", ["-x", processName]).catch(() => {});
  await sleep(1_000);
  await run("open", [resolvedAppPath]);
  await waitForProcess(processName, 30_000);
  await run("osascript", ["-e", `tell application "${processName}" to quit`]);
  await waitForExit(processName, 15_000);
  console.log(`Release launch smoke passed for ${resolvedAppPath}`);
} finally {
  await run("pkill", ["-x", processName]).catch(() => {});
}

async function waitForProcess(name, timeoutMs) {
  await waitFor(async () => {
    const output = await run("pgrep", ["-x", name]).catch(() => "");
    return output.trim().length > 0;
  }, `${name} to launch`, timeoutMs);
}

async function waitForExit(name, timeoutMs) {
  await waitFor(async () => {
    const output = await run("pgrep", ["-x", name]).catch(() => "");
    return output.trim().length === 0;
  }, `${name} to quit`, timeoutMs);
}

async function waitFor(predicate, label, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await sleep(500);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`${command} failed: ${stderr || stdout || error.message}`));
        return;
      }
      resolve(stdout);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
