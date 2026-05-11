#!/usr/bin/env node

import { appendFile, readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";

async function findResultFiles(root) {
  const out = [];
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      const nested = await readdir(full, { withFileTypes: true }).catch(() => []);
      for (const inner of nested) {
        if (inner.isFile() && inner.name.endsWith(".json")) {
          out.push(path.join(full, inner.name));
        }
      }
    } else if (entry.isFile() && entry.name.endsWith(".json")) {
      out.push(full);
    }
  }
  return out;
}

async function loadRecords(files) {
  const records = [];
  for (const file of files) {
    try {
      const raw = await readFile(file, "utf8");
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        for (const item of parsed) {
          if (item && typeof item === "object") {
            records.push({ ...item, source: path.basename(path.dirname(file)) });
          }
        }
      }
    } catch (error) {
      console.error(`smoke summarizer: skipping ${file}: ${error.message}`);
    }
  }
  return records;
}

function renderSummary(records) {
  if (records.length === 0) {
    return [
      "## Smoke Flake Summary",
      "",
      "_No smoke result records were found._",
      "",
    ].join("\n");
  }
  const lines = [
    "## Smoke Flake Summary",
    "",
    "| Smoke | Result | Attempts | Retried | Duration |",
    "| --- | --- | ---: | :---: | ---: |",
  ];
  let retried = 0;
  let failed = 0;
  for (const record of records) {
    const status = record.passed ? "PASS" : "FAIL";
    const attempts = record.attempts ?? 1;
    const retriedCell = record.retried ? "yes" : "no";
    const duration = typeof record.duration_ms === "number"
      ? `${(record.duration_ms / 1000).toFixed(1)}s`
      : "-";
    const name = record.name ?? record.source ?? "unknown";
    if (record.retried) retried += 1;
    if (!record.passed) failed += 1;
    lines.push(`| \`${name}\` | ${status} | ${attempts} | ${retriedCell} | ${duration} |`);
  }
  lines.push("");
  lines.push(`**Totals:** ${records.length} smoke run(s), ${retried} retried, ${failed} failed.`);
  lines.push("");
  return lines.join("\n");
}

async function main() {
  const root = process.argv[2] ?? "smoke-results";
  await stat(root).catch(() => null);
  const files = await findResultFiles(root);
  const records = await loadRecords(files);
  const markdown = renderSummary(records);
  const summary = process.env.GITHUB_STEP_SUMMARY;
  if (summary) {
    await appendFile(summary, markdown);
  } else {
    process.stdout.write(markdown);
  }
}

main().catch((error) => {
  console.error(`smoke summarizer crashed: ${error?.message ?? error}`);
  process.exit(0);
});
