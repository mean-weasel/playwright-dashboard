import { execFile } from "node:child_process";

export const osascriptPath = "/usr/bin/osascript";

const defaultProbeProcess = "Finder";

export async function runAccessibilityPreflight({
  probeProcess = process.env.ACCESSIBILITY_PROBE_PROCESS ?? defaultProbeProcess,
  quiet = false,
} = {}) {
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

  try {
    const probeResult = await run(osascriptPath, ["-e", probe]);
    if (!quiet) {
      console.log("Accessibility probe passed.");
      console.log(probeResult.trim());
      console.log(`Node.js binary: ${process.execPath}`);
      console.log(`osascript binary: ${osascriptPath}`);
    }
    return probeResult;
  } catch (error) {
    const output = error.stderr || error.stdout || error.message;
    if (isAccessibilityDenied(output)) {
      throw new Error(await accessibilityHelp(output, probeProcess));
    }
    throw new Error(output);
  }
}

export function isAccessibilityDenied(output) {
  return output.includes("-25211") || output.includes("not allowed assistive access");
}

export function staticAccessibilityHelp() {
  return [
    "macOS denied assistive access for the process running this GUI QA harness.",
    "Grant Accessibility access to every process identity in the launch chain: terminal/editor, Node.js, osascript, and any wrapper/helper.",
    `Node.js binary: ${process.execPath}`,
    `osascript binary: ${osascriptPath}`,
    "System Settings > Privacy & Security > Accessibility",
    "After changing Accessibility settings, quit and reopen the terminal/editor before rerunning QA.",
  ].join("\n");
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

function appleScriptString(value) {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

async function accessibilityHelp(output, probeProcess) {
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
