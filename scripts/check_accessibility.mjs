#!/usr/bin/env node

import { execFile } from "node:child_process";

const probeProcess = process.env.ACCESSIBILITY_PROBE_PROCESS ?? "Finder";
const probeProcessLiteral = appleScriptString(probeProcess);
const probe = `
set probeProcessName to ${probeProcessLiteral}
tell application "System Events"
  if not (exists process probeProcessName) then error "Probe process is not running: " & probeProcessName
  tell process probeProcessName
    set windowCount to count of windows
    set menuBarCount to count of menu bars
  end tell
end tell
return "process=" & probeProcessName & " windows=" & windowCount & " menuBars=" & menuBarCount
`;
const osascriptPath = "/usr/bin/osascript";

try {
  const probeResult = await run(osascriptPath, ["-e", probe]);
  console.log("Accessibility probe passed.");
  console.log(probeResult.trim());
  console.log(`Node.js binary: ${process.execPath}`);
  console.log(`osascript binary: ${osascriptPath}`);
} catch (error) {
  const output = error.stderr || error.stdout || error.message;
  if (isAccessibilityDenied(output)) {
    console.error(await accessibilityHelp(output));
    process.exit(1);
  }
  console.error(output);
  process.exit(error.code || 1);
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, (error, stdout, stderr) => {
      if (error) {
        error.stdout = stdout;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve(stdout);
    });
  });
}

function isAccessibilityDenied(output) {
  return output.includes("-25211") || output.includes("not allowed assistive access");
}

function appleScriptString(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

async function accessibilityHelp(output) {
  const rows = await accessibilityRows().catch((error) => {
    return `Unable to inspect TCC database: ${error.message}`;
  });
  return [
    "macOS denied assistive access for this shell -> node -> osascript probe.",
    "",
    "Grant Accessibility access under:",
    "System Settings > Privacy & Security > Accessibility",
    "",
    "Add or enable every process identity in the launch chain that appears on this machine:",
    "- The terminal or editor that launched the command, such as Terminal, iTerm, VS Code, Cursor, or Codex.",
    `- The Node.js binary running this harness: ${process.execPath}`,
    `- The AppleScript runner: ${osascriptPath}`,
    "- Any wrapper or helper binary used to start the command.",
    "",
    `This probe tried to inspect System Events process "${probeProcess}", which matches the access level used by GUI QA.`,
    "",
    "Recorded Accessibility TCC rows for this launch chain:",
    rows || "No matching rows found.",
    "",
    "After changing Accessibility settings, quit and reopen the terminal/editor before rerunning QA.",
    "",
    output,
  ].join("\n");
}

async function accessibilityRows() {
  const database = "/Library/Application Support/com.apple.TCC/TCC.db";
  const codexPathPattern = "%/codex";
  const query = `
select client || ' client_type=' || client_type || ' auth_value=' || auth_value || ' auth_reason=' || auth_reason
from access
where service='kTCCServiceAccessibility'
  and (
    client='${sqlString(process.execPath)}'
    or client='${sqlString(osascriptPath)}'
    or client='com.apple.Terminal'
    or client like '${sqlString(codexPathPattern)}'
  )
order by client;
`;
  return run("sqlite3", [database, query]);
}

function sqlString(value) {
  return value.replaceAll("'", "''");
}
