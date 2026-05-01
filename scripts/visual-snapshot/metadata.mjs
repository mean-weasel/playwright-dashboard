import { mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import { fsTempDir, run } from "./process.mjs";

export async function writeManifest({
  appPath,
  artifactDir,
  baselineDir,
  cases,
  enforceVisualDiffs = false,
  visualDiffThreshold = 0.01,
  visualDiffPixelThreshold = 2,
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
      baseline: await baselineStatus({
        baselineDir,
        filePath,
        filename,
        hash,
        visualDiffThreshold,
        visualDiffPixelThreshold,
      }),
    });
  }

  const manifest = {
    generatedAt: new Date().toISOString(),
    mode: enforceVisualDiffs ? "visual-diff-enforced" : "artifact-only",
    structuralAssertions: "blocking",
    visualDiffs: {
      enforcement: enforceVisualDiffs ? "blocking" : "report-only",
      threshold: visualDiffThreshold,
      pixelThreshold: visualDiffPixelThreshold,
    },
    appPath,
    baselineDir,
    snapshots,
  };
  await writeJson(path.join(artifactDir, "manifest.json"), manifest);
  await writeMarkdownSummary(path.join(artifactDir, "summary.md"), manifest);
  assertVisualDiffs(manifest);
}

async function baselineStatus({
  baselineDir,
  filePath,
  filename,
  hash,
  visualDiffThreshold,
  visualDiffPixelThreshold,
}) {
  if (!baselineDir) return { status: "not-configured" };

  const baselinePath = path.join(baselineDir, filename);
  let baselineHash;
  try {
    baselineHash = await sha256(baselinePath);
  } catch {
    return { status: "missing", path: baselinePath };
  }

  if (baselineHash === hash) {
    return {
      status: "unchanged",
      path: baselinePath,
      sha256: baselineHash,
      diff: {
        mismatchedPixels: 0,
        totalPixels: 0,
        ratio: 0,
        threshold: visualDiffThreshold,
        pixelThreshold: visualDiffPixelThreshold,
      },
    };
  }

  const diff = await pixelDiff(filePath, baselinePath, {
    visualDiffThreshold,
    visualDiffPixelThreshold,
  });

  return {
    status:
      diff.status === "dimension-mismatch"
        ? "dimension-mismatch"
        : diff.ratio > visualDiffThreshold
          ? "changed-over-threshold"
          : "changed-within-threshold",
    path: baselinePath,
    sha256: baselineHash,
    bytesChanged: await byteDelta(filePath, baselinePath),
    diff,
  };
}

function assertVisualDiffs(manifest) {
  if (manifest.visualDiffs?.enforcement !== "blocking") return;

  const failures = [];
  if (!manifest.baselineDir) {
    failures.push("baseline directory is not configured");
  }

  for (const snapshot of manifest.snapshots) {
    const status = snapshot.baseline?.status;
    if (status === "missing") {
      failures.push(`${snapshot.filename}: missing baseline`);
    } else if (status === "dimension-mismatch") {
      const diff = snapshot.baseline.diff;
      failures.push(
        `${snapshot.filename}: dimension mismatch (${diff.currentWidth}x${diff.currentHeight} current, ${diff.baselineWidth}x${diff.baselineHeight} baseline)`,
      );
    } else if (status === "changed-over-threshold") {
      failures.push(
        `${snapshot.filename}: ${formatPercent(
          snapshot.baseline.diff.ratio,
        )} pixels changed, threshold ${formatPercent(manifest.visualDiffs.threshold)}`,
      );
    }
  }

  if (failures.length > 0) {
    throw new Error(
      [
        "Visual snapshot diffs exceeded the configured blocking policy:",
        ...failures.map((failure) => `- ${failure}`),
      ].join("\n"),
    );
  }
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

async function pixelDiff(filePath, baselinePath, options) {
  const tmpRoot = await fsTempDir("playwright-dashboard-visual-diff-");
  try {
    const currentBmp = path.join(tmpRoot, "current.bmp");
    const baselineBmp = path.join(tmpRoot, "baseline.bmp");
    await Promise.all([
      convertToBmp(filePath, currentBmp),
      convertToBmp(baselinePath, baselineBmp),
    ]);
    const [current, baseline] = await Promise.all([
      readBmpPixels(currentBmp),
      readBmpPixels(baselineBmp),
    ]);

    const base = {
      threshold: options.visualDiffThreshold,
      pixelThreshold: options.visualDiffPixelThreshold,
      currentWidth: current.width,
      currentHeight: current.height,
      baselineWidth: baseline.width,
      baselineHeight: baseline.height,
    };

    if (current.width !== baseline.width || current.height !== baseline.height) {
      return {
        ...base,
        status: "dimension-mismatch",
        mismatchedPixels: null,
        totalPixels: null,
        ratio: 1,
      };
    }

    let mismatchedPixels = 0;
    for (let index = 0; index < current.pixels.length; index += 4) {
      const redDelta = Math.abs(current.pixels[index] - baseline.pixels[index]);
      const greenDelta = Math.abs(current.pixels[index + 1] - baseline.pixels[index + 1]);
      const blueDelta = Math.abs(current.pixels[index + 2] - baseline.pixels[index + 2]);
      const alphaDelta = Math.abs(current.pixels[index + 3] - baseline.pixels[index + 3]);
      if (
        redDelta > options.visualDiffPixelThreshold ||
        greenDelta > options.visualDiffPixelThreshold ||
        blueDelta > options.visualDiffPixelThreshold ||
        alphaDelta > options.visualDiffPixelThreshold
      ) {
        mismatchedPixels += 1;
      }
    }

    const totalPixels = current.width * current.height;
    return {
      ...base,
      status: "compared",
      mismatchedPixels,
      totalPixels,
      ratio: totalPixels === 0 ? 0 : mismatchedPixels / totalPixels,
    };
  } finally {
    await rm(tmpRoot, { recursive: true, force: true });
  }
}

async function convertToBmp(inputPath, outputPath) {
  await run("sips", ["-s", "format", "bmp", inputPath, "--out", outputPath]);
}

async function readBmpPixels(filePath) {
  const buffer = await readFile(filePath);
  if (buffer.toString("ascii", 0, 2) !== "BM") {
    throw new Error(`Unsupported BMP signature for ${filePath}`);
  }

  const pixelOffset = buffer.readUInt32LE(10);
  const dibHeaderSize = buffer.readUInt32LE(14);
  const width = buffer.readInt32LE(18);
  const signedHeight = buffer.readInt32LE(22);
  const planes = buffer.readUInt16LE(26);
  const bitsPerPixel = buffer.readUInt16LE(28);
  const compression = buffer.readUInt32LE(30);
  if (
    dibHeaderSize < 40 ||
    planes !== 1 ||
    ![0, 3].includes(compression) ||
    ![24, 32].includes(bitsPerPixel) ||
    (compression === 3 && bitsPerPixel !== 32) ||
    width <= 0 ||
    signedHeight === 0
  ) {
    throw new Error(
      `Unsupported BMP format for ${filePath}: ${bitsPerPixel} bpp, compression ${compression}`,
    );
  }

  const height = Math.abs(signedHeight);
  const topDown = signedHeight < 0;
  const bytesPerPixel = bitsPerPixel / 8;
  const rowStride = Math.ceil((width * bytesPerPixel) / 4) * 4;
  const pixels = Buffer.alloc(width * height * 4);
  const bitMasks = compression === 3
    ? readBmpBitMasks(buffer, dibHeaderSize, pixelOffset)
    : null;

  for (let y = 0; y < height; y += 1) {
    const sourceY = topDown ? y : height - y - 1;
    const rowOffset = pixelOffset + sourceY * rowStride;
    for (let x = 0; x < width; x += 1) {
      const sourceOffset = rowOffset + x * bytesPerPixel;
      const targetOffset = (y * width + x) * 4;
      if (bitMasks) {
        const value = buffer.readUInt32LE(sourceOffset);
        pixels[targetOffset] = extractBmpChannel(value, bitMasks.red);
        pixels[targetOffset + 1] = extractBmpChannel(value, bitMasks.green);
        pixels[targetOffset + 2] = extractBmpChannel(value, bitMasks.blue);
        pixels[targetOffset + 3] =
          bitMasks.alpha.mask === 0 ? 255 : extractBmpChannel(value, bitMasks.alpha);
      } else {
        pixels[targetOffset] = buffer[sourceOffset + 2];
        pixels[targetOffset + 1] = buffer[sourceOffset + 1];
        pixels[targetOffset + 2] = buffer[sourceOffset];
        pixels[targetOffset + 3] =
          bitsPerPixel === 32 ? buffer[sourceOffset + 3] : 255;
      }
    }
  }

  return { width, height, pixels };
}

function readBmpBitMasks(buffer, dibHeaderSize, pixelOffset) {
  const maskOffset = 14 + 40;
  if (maskOffset + 12 > pixelOffset) {
    throw new Error("Unsupported BMP bitfield layout: missing color masks");
  }

  const masksInsideHeader = dibHeaderSize >= 56;
  const redMask = buffer.readUInt32LE(maskOffset);
  const greenMask = buffer.readUInt32LE(maskOffset + 4);
  const blueMask = buffer.readUInt32LE(maskOffset + 8);
  const hasAlphaMask = masksInsideHeader || maskOffset + 16 <= pixelOffset;
  const alphaMask = hasAlphaMask ? buffer.readUInt32LE(maskOffset + 12) : 0;
  return {
    red: bmpChannelMask(redMask),
    green: bmpChannelMask(greenMask),
    blue: bmpChannelMask(blueMask),
    alpha: bmpChannelMask(alphaMask),
  };
}

function bmpChannelMask(mask) {
  const unsignedMask = mask >>> 0;
  if (unsignedMask === 0) return { mask: 0, shift: 0, max: 0 };

  let shift = 0;
  while (((unsignedMask >>> shift) & 1) === 0) {
    shift += 1;
  }

  let bits = 0;
  while (((unsignedMask >>> (shift + bits)) & 1) === 1) {
    bits += 1;
  }

  return {
    mask: unsignedMask,
    shift,
    max: 2 ** bits - 1,
  };
}

function extractBmpChannel(value, channel) {
  if (channel.mask === 0 || channel.max === 0) return 0;
  const raw = ((value & channel.mask) >>> channel.shift) >>> 0;
  return Math.round((raw / channel.max) * 255);
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
    `Structural assertions: \`${manifest.structuralAssertions || "not recorded"}\``,
    `Visual diffs: \`${manifest.visualDiffs?.enforcement || "report-only"}\``,
    `Diff threshold: \`${
      manifest.visualDiffs?.threshold === undefined
        ? "not recorded"
        : formatPercent(manifest.visualDiffs.threshold)
    }\``,
    `Pixel threshold: \`${manifest.visualDiffs?.pixelThreshold ?? "not recorded"}\``,
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
  if (baseline.status === "changed-within-threshold") {
    return `within threshold (${formatPercent(baseline.diff.ratio)}, ${formatDelta(
      baseline.bytesChanged,
    )})`;
  }
  if (baseline.status === "changed-over-threshold") {
    return `over threshold (${formatPercent(baseline.diff.ratio)}, ${formatDelta(
      baseline.bytesChanged,
    )})`;
  }
  if (baseline.status === "dimension-mismatch") {
    return `dimension mismatch (${baseline.diff.currentWidth}x${baseline.diff.currentHeight} current, ${baseline.diff.baselineWidth}x${baseline.diff.baselineHeight} baseline)`;
  }
  return baseline.status;
}

function formatPercent(value) {
  return `${(value * 100).toFixed(2)}%`;
}

function formatDelta(value) {
  if (value > 0) return `+${value} bytes`;
  return `${value} bytes`;
}

export async function readManifestSummary(manifestPath) {
  return markdownSummary(JSON.parse(await readFile(manifestPath, "utf8")));
}
