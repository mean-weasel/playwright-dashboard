#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const siteDir = path.join(root, "site");
const requiredFiles = [
  "index.html",
  "docs.html",
  "media.html",
  "styles.css",
];

for (const relative of requiredFiles) {
  const file = path.join(siteDir, relative);
  if (!fs.existsSync(file)) {
    throw new Error(`Missing site file: site/${relative}`);
  }
}

const htmlFiles = requiredFiles.filter((file) => file.endsWith(".html"));
for (const relative of htmlFiles) {
  const file = path.join(siteDir, relative);
  const html = fs.readFileSync(file, "utf8");
  for (const token of ["<!doctype html>", "<html", "</html>", "Playwright Dashboard"]) {
    if (!html.toLowerCase().includes(token.toLowerCase())) {
      throw new Error(`site/${relative} is missing ${token}`);
    }
  }

  const localTargets = [
    ...[...html.matchAll(/href="([^"#][^"]*)"/g)].map((match) => match[1]),
    ...[...html.matchAll(/src="([^"#][^"]*)"/g)].map((match) => match[1]),
  ].filter((target) => !target.startsWith("http") && !target.startsWith("mailto:"));
  for (const targetRef of localTargets) {
    const targetPath = targetRef.split("#")[0];
    if (!targetPath || targetPath === "./") {
      continue;
    }
    const target = path.join(siteDir, targetPath);
    if (!fs.existsSync(target)) {
      throw new Error(`site/${relative} references missing local target: ${targetRef}`);
    }
  }
}

console.log("Docs site validation passed");
