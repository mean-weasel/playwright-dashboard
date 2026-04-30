import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import { run } from "./process.mjs";

export async function writeManifest({
  appPath,
  artifactDir,
  baselineDir,
  cases,
}) {
  const snapshots = [];
  for (const testCase of cases) {
    const filename = `${testCase.name}.png`;
    const filePath = path.join(artifactDir, filename);
    const fileStat = await stat(filePath);
    const dimensions = await imageDimensions(filePath);
    const hash = await sha256(filePath);
    snapshots.push({
      name: testCase.name,
      filename,
      window: testCase.window,
      width: dimensions.width,
      height: dimensions.height,
      bytes: fileStat.size,
      sha256: hash,
      baseline: await baselineStatus({ baselineDir, filePath, filename, hash }),
    });
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    mode: "artifact-only",
    appPath,
    baselineDir,
    snapshots,
  };
  await writeJson(path.join(artifactDir, "manifest.json"), manifest);
  await writeMarkdownSummary(path.join(artifactDir, "summary.md"), manifest);
}

async function baselineStatus({ baselineDir, filePath, filename, hash }) {
  if (!baselineDir) return { status: "not-configured" };

  const baselinePath = path.join(baselineDir, filename);
  let baselineHash;
  try {
    baselineHash = await sha256(baselinePath);
  } catch {
    return { status: "missing", path: baselinePath };
  }

  if (baselineHash === hash) {
    return { status: "unchanged", path: baselinePath, sha256: baselineHash };
  }

  return {
    status: "changed",
    path: baselinePath,
    sha256: baselineHash,
    bytesChanged: await byteDelta(filePath, baselinePath),
  };
}

async function imageDimensions(filePath) {
  const output = await run("sips", ["-g", "pixelWidth", "-g", "pixelHeight", filePath]);
  const width = Number(output.match(/pixelWidth:\s+(\d+)/)?.[1]);
  const height = Number(output.match(/pixelHeight:\s+(\d+)/)?.[1]);
  if (!Number.isFinite(width) || !Number.isFinite(height)) {
    throw new Error(`Unable to read image dimensions for ${filePath}`);
  }
  return { width, height };
}

async function sha256(filePath) {
  const output = await run("shasum", ["-a", "256", filePath]);
  return output.trim().split(/\s+/)[0];
}

async function byteDelta(filePath, baselinePath) {
  const [current, baseline] = await Promise.all([stat(filePath), stat(baselinePath)]);
  return current.size - baseline.size;
}

async function writeJson(filePath, value) {
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function writeMarkdownSummary(filePath, manifest) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, `${markdownSummary(manifest)}\n`, "utf8");
}

export function markdownSummary(manifest) {
  const lines = [
    "## Visual Snapshots",
    "",
    `Mode: \`${manifest.mode}\``,
    `Generated: \`${manifest.generatedAt}\``,
    `Baseline: \`${manifest.baselineDir || "not configured"}\``,
    "",
    "| Snapshot | Window | Size | Bytes | Baseline |",
    "| --- | --- | ---: | ---: | --- |",
  ];

  for (const snapshot of manifest.snapshots) {
    const size = `${snapshot.width} x ${snapshot.height}`;
    lines.push(
      `| \`${snapshot.filename}\` | ${snapshot.window} | ${size} | ${
        snapshot.bytes
      } | ${baselineLabel(snapshot.baseline)} |`,
    );
  }

  return lines.join("\n");
}

function baselineLabel(baseline) {
  if (!baseline || baseline.status === "not-configured") return "not configured";
  if (baseline.status === "changed") return `changed (${formatDelta(baseline.bytesChanged)})`;
  return baseline.status;
}

function formatDelta(value) {
  if (value > 0) return `+${value} bytes`;
  return `${value} bytes`;
}

export async function readManifestSummary(manifestPath) {
  return markdownSummary(JSON.parse(await readFile(manifestPath, "utf8")));
}
