#!/usr/bin/env node

import { spawn } from "node:child_process";
import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");

function parseArgs(argv) {
  let name = null;
  let resultsFile = null;
  let i = 0;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg === "--name" && i + 1 < argv.length) {
      name = argv[i + 1];
      i += 2;
    } else if (arg === "--results-file" && i + 1 < argv.length) {
      resultsFile = argv[i + 1];
      i += 2;
    } else if (arg === "--") {
      i += 1;
      break;
    } else {
      break;
    }
  }
  const rest = argv.slice(i);
  if (rest.length === 0) {
    throw new Error("Usage: run_smoke_with_retry.mjs [--name <id>] [--results-file <path>] -- <command> [args...]");
  }
  return { name, resultsFile, command: rest[0], commandArgs: rest.slice(1) };
}

function inferSmokeName(command) {
  return path
    .basename(command)
    .replace(/\.[^.]+$/, "")
    .replace(/^smoke_/, "");
}

function runOnce(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: "inherit" });
    child.on("error", (error) => {
      console.error(`smoke wrapper: failed to spawn ${command}: ${error.message}`);
      resolve({ code: 1, signal: null });
    });
    child.on("exit", (code, signal) => {
      resolve({ code: code ?? (signal ? 1 : 0), signal });
    });
  });
}

function resetState() {
  return new Promise((resolve) => {
    const child = spawn("pkill", ["-x", "PlaywrightDashboard"], { stdio: "ignore" });
    child.on("error", () => resolve());
    child.on("exit", () => resolve());
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function appendResult(resultsFile, record) {
  await mkdir(path.dirname(resultsFile), { recursive: true });
  let existing = [];
  try {
    const raw = await readFile(resultsFile, "utf8");
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      existing = parsed;
    }
  } catch {
    existing = [];
  }
  existing.push(record);
  await writeFile(resultsFile, `${JSON.stringify(existing, null, 2)}\n`);
}

async function appendStepSummary(record) {
  const summary = process.env.GITHUB_STEP_SUMMARY;
  if (!summary) return;
  const status = record.passed ? "passed" : "FAILED";
  const tag = record.retried ? " (retried)" : "";
  const line = `- \`${record.name}\`: ${status}${tag} after ${record.attempts} attempt(s) in ${record.duration_ms} ms\n`;
  await appendFile(summary, line).catch(() => {});
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const name = args.name ?? inferSmokeName(args.command);
  const resultsFile =
    args.resultsFile ??
    process.env.SMOKE_RESULTS_FILE ??
    path.join(repoRoot, "dist", "smoke-results.json");
  const retryCount = Math.max(0, Number.parseInt(process.env.SMOKE_RETRY_COUNT ?? "0", 10) || 0);
  const maxAttempts = retryCount + 1;
  const started = Date.now();
  let attempts = 0;
  let lastCode = 0;
  while (attempts < maxAttempts) {
    attempts += 1;
    if (attempts > 1) {
      console.error(`smoke wrapper: attempt ${attempts}/${maxAttempts} for ${name}; resetting state`);
      await resetState();
      await sleep(1_500);
    }
    const { code } = await runOnce(args.command, args.commandArgs);
    lastCode = code;
    if (code === 0) {
      break;
    }
    if (attempts < maxAttempts) {
      console.error(`smoke wrapper: ${name} failed with exit ${code}; will retry`);
    }
  }
  const finished = Date.now();
  const record = {
    name,
    command: args.command,
    started_at: new Date(started).toISOString(),
    finished_at: new Date(finished).toISOString(),
    duration_ms: finished - started,
    attempts,
    retried: attempts > 1,
    passed: lastCode === 0,
    exit_code: lastCode,
  };
  await appendResult(resultsFile, record);
  await appendStepSummary(record);
  process.exit(lastCode);
}

main().catch((error) => {
  console.error(`smoke wrapper crashed: ${error?.message ?? error}`);
  process.exit(1);
});
