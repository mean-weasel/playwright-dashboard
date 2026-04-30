import { execFile } from "node:child_process";
import { mkdtemp } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const accessibilityHelp = [
  "macOS denied assistive access for the process running this script.",
  "Grant Accessibility access to your terminal app and the Node.js binary that runs this harness.",
  `Node.js binary: ${process.execPath}`,
  "System Settings > Privacy & Security > Accessibility",
].join("\n");

export function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (error) {
        const output = `${stderr || stdout || error.message}`;
        error.message = isAccessibilityDenied(output)
          ? `${accessibilityHelp}\n\n${output}`
          : `${error.message}\n${stderr}`;
        reject(error);
        return;
      }
      resolve(stdout.trim());
    });
  });
}

function isAccessibilityDenied(output) {
  return output.includes("-25211") || output.includes("not allowed assistive access");
}

export function runAppleScript(source) {
  return run("osascript", ["-e", source]);
}

export function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export async function fsTempDir(prefix) {
  return mkdtemp(path.join(os.tmpdir(), prefix));
}

export async function stopProcess(process) {
  if (!process || process.exitCode !== null) return;
  process.kill("SIGTERM");
  await new Promise((resolve) => {
    const timeout = setTimeout(resolve, 2_000);
    process.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });
  });
}

export async function waitFor(predicate, label, timeoutMs = 15_000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await predicate()) return;
    await sleep(250);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

export function json(url) {
  return new Promise((resolve, reject) => {
    http.get(url, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    }).on("error", reject);
  });
}

export async function freePort() {
  return new Promise((resolve, reject) => {
    const server = http.createServer();
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      server.close(() => resolve(port));
    });
    server.on("error", reject);
  });
}
