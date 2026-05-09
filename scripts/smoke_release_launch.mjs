#!/usr/bin/env node

import { execFile, spawn } from "node:child_process";
import path from "node:path";

const appPath = process.argv[2];
if (!appPath) {
  throw new Error("Usage: smoke_release_launch.mjs /path/to/PlaywrightDashboard.app");
}

const resolvedAppPath = path.resolve(appPath);
const executablePath = path.join(
  resolvedAppPath,
  "Contents",
  "MacOS",
  "PlaywrightDashboard",
);
const processName = "PlaywrightDashboard";
const launchTimeoutMs = Number(process.env.RELEASE_LAUNCH_TIMEOUT_MS ?? 90_000);
const quitTimeoutMs = Number(process.env.RELEASE_QUIT_TIMEOUT_MS ?? 30_000);

let directProcess = null;

try {
  log("Cleaning up existing app process");
  await run("pkill", ["-x", processName]).catch(() => {});
  await sleep(1_000);

  log(`Launching app through LaunchServices: ${resolvedAppPath}`);
  await run("open", ["-n", resolvedAppPath]);
  try {
    await waitForProcess(processName, launchTimeoutMs);
  } catch (error) {
    log(`LaunchServices did not expose ${processName}: ${error.message}`);
    log("Trying direct executable fallback");
    directProcess = spawn(executablePath, [], {
      detached: true,
      stdio: "ignore",
    });
    directProcess.unref();
    await waitForProcess(processName, Math.min(30_000, launchTimeoutMs));
  }

  log("Quitting app");
  await run("osascript", ["-e", `tell application "${processName}" to quit`]).catch(
    (error) => log(`AppleScript quit failed: ${error.message}`),
  );
  if (directProcess && directProcess.exitCode === null) {
    directProcess.kill("SIGTERM");
  }
  await waitForExit(processName, quitTimeoutMs);
  console.log(`Release launch smoke passed for ${resolvedAppPath}`);
} catch (error) {
  console.error(await diagnostics(error));
  throw error;
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

async function diagnostics(error) {
  const [processes, bundleInfo, quarantine] = await Promise.all([
    run("ps", ["-axo", "pid,ppid,etime,command"]).catch((diagError) => diagError.message),
    run("/usr/libexec/PlistBuddy", [
      "-c",
      "Print :CFBundleExecutable",
      path.join(resolvedAppPath, "Contents", "Info.plist"),
    ]).catch((diagError) => diagError.message),
    run("xattr", ["-l", resolvedAppPath]).catch((diagError) => diagError.message),
  ]);
  return [
    `Release launch smoke failed: ${error.message}`,
    `app=${resolvedAppPath}`,
    `executable=${executablePath}`,
    `CFBundleExecutable=${bundleInfo.trim()}`,
    `xattr=${quarantine.trim() || "<none>"}`,
    "matching processes:",
    processes
      .split("\n")
      .filter((line) => line.includes(processName))
      .join("\n") || "<none>",
  ].join("\n");
}

function log(message) {
  console.log(`[release-smoke] ${message}`);
}
