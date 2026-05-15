#!/usr/bin/env node

import { execFile } from "node:child_process";
import { copyFile, mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const sourceDir = path.resolve(
  process.env.REALISTIC_E2E_ARTIFACT_DIR ?? path.join(repoRoot, "dist", "realistic-e2e-artifacts"),
);
const outputDir = path.resolve(
  process.env.DEMO_MEDIA_DIR ?? path.join(repoRoot, "dist", "docs-media", "operator-workbench"),
);
const fromExisting =
  process.argv.includes("--from-existing") || process.env.DEMO_MEDIA_FROM_EXISTING === "1";
const requiredFiles = [
  "dashboard-window.png",
  "scenario.json",
  "progress.log",
  "ui-snapshot.txt",
  "expanded-ready.json",
];

if (!fromExisting) {
  await run("make", ["smoke-realistic-e2e"], {
    cwd: repoRoot,
    env: {
      ...process.env,
      RUN_REALISTIC_E2E_SMOKE: "1",
      SMOKE_ARTIFACT_DIR: sourceDir,
    },
    timeout: 180_000,
  });
}

await assertSourceArtifacts();
await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });

const media = [];
for (const filename of requiredFiles) {
  const source = path.join(sourceDir, filename);
  const destination = path.join(outputDir, filename);
  await copyFile(source, destination);
  const fileStat = await stat(destination);
  media.push({
    filename,
    bytes: fileStat.size,
    purpose: purposeFor(filename),
  });
}

const scenario = JSON.parse(await readFile(path.join(outputDir, "scenario.json"), "utf8"));
const manifest = {
  generatedAt: new Date().toISOString(),
  source: {
    scenario: "operator-workbench realistic E2E smoke",
    sourceDir,
    command: fromExisting
      ? "DEMO_MEDIA_FROM_EXISTING=1 make demo-media"
      : "RUN_REALISTIC_E2E_SMOKE=1 make smoke-realistic-e2e && make demo-media",
  },
  outputDir,
  pagesImplementation: "out-of-scope-for-current-tranche",
  curationRules: [
    "Do not commit generated binary media without explicit approval.",
    "Use artifacts from isolated local fixture sessions only.",
    "Regenerate media after visible Dashboard or fixture UI changes.",
    "Review screenshots/video for local paths, ports, URLs, or unexpected private content before publication.",
  ],
  scenario,
  media,
  nextPlannedMedia: [
    {
      name: "Short MP4/GIF demo",
      source: "Future extension of the realistic smoke or recording export smoke.",
      status: "planned",
    },
  ],
};

await writeFile(path.join(outputDir, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
await writeFile(path.join(outputDir, "summary.md"), markdownSummary(manifest));
console.log(`Demo media artifacts written to ${outputDir}`);

async function assertSourceArtifacts() {
  const existing = new Set(await readdir(sourceDir).catch(() => []));
  const missing = requiredFiles.filter((filename) => !existing.has(filename));
  if (missing.length > 0) {
    throw new Error(
      `Missing realistic E2E artifacts in ${sourceDir}: ${missing.join(", ")}. Run RUN_REALISTIC_E2E_SMOKE=1 SMOKE_ARTIFACT_DIR=${sourceDir} make smoke-realistic-e2e first.`,
    );
  }
}

function purposeFor(filename) {
  switch (filename) {
    case "dashboard-window.png":
      return "Primary future landing/docs screenshot showing Playwright Dashboard observing the realistic fixture in Safe mode.";
    case "scenario.json":
      return "Machine-readable scenario metadata, local URLs, session id, and artifact inventory.";
    case "progress.log":
      return "Human-readable smoke timeline for docs and debugging.";
    case "ui-snapshot.txt":
      return "Accessibility snapshot evidence for Dashboard UI state.";
    case "expanded-ready.json":
      return "Readiness payload proving Safe mode expanded-session observation.";
    default:
      return "Supporting artifact.";
  }
}

function markdownSummary(manifest) {
  return [
    "# Operator Workbench Demo Media",
    "",
    `Generated: ${manifest.generatedAt}`,
    "",
    `Source command: \`${manifest.source.command}\``,
    "",
    "| File | Bytes | Purpose |",
    "| --- | ---: | --- |",
    ...manifest.media.map((item) => `| ${item.filename} | ${item.bytes} | ${item.purpose} |`),
    "",
    "## Curation Rules",
    "",
    ...manifest.curationRules.map((rule) => `- ${rule}`),
    "",
  ].join("\n");
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { encoding: "utf8", ...options }, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}
