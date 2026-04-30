#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";

import { markdownSummary } from "./metadata.mjs";

const manifestPath = process.argv[2] || path.join("dist", "visual-snapshots", "manifest.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

console.log(markdownSummary(manifest));
