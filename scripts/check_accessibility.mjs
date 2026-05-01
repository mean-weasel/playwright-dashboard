#!/usr/bin/env node

import { runAccessibilityPreflight } from "./visual-snapshot/accessibility.mjs";

try {
  await runAccessibilityPreflight();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
