# Telemetry Policy

**Playwright Dashboard does not collect or send telemetry.**

The app runs entirely on the user's machine. It does not phone home for crash
reports, usage analytics, activation pings, or any other signal. There is no
backend service operated by the project that receives information about
installs, sessions, dashboard activity, or app health.

The only network traffic the app initiates is the **Check for Updates** menu
item, which opens the GitHub Releases page in the user's default browser. The
browser, not the app, makes that request.

## What "local-only" means in practice

- Diagnostics are exported to a local file on demand from
  **Settings → Diagnostics → Export Diagnostics**. They never leave the
  machine unless the user manually shares the export.
- Crashes are logged to macOS's standard crash reporter (`~/Library/Logs/`
  / `Console.app`). They are not forwarded to any service.
- Recordings, screenshots, and session metadata live in
  `~/Library/Application Support/PlaywrightDashboard/`,
  `~/Downloads/PlaywrightDashboard Recordings/`, and the SwiftData store.
  None of these are uploaded anywhere.

## Why

Playwright Dashboard is a developer tool that observes locally-running
browser sessions, often during sensitive work (auth, customer data,
production debugging). Shipping a telemetry SDK on top of that creates a
risk profile and a privacy surface that this project does not want to
operate. Local-first matches what users of this kind of tool expect.

## If the policy ever changes

Any future addition of telemetry must:

1. Be **opt-in** (off by default; user must explicitly enable in Settings).
2. Be scoped to a documented event list — no open-ended SDK auto-capture.
3. Include a clear in-app privacy disclosure before any data is sent.
4. Be discussed in a follow-up issue with the user-visible scope laid out
   before implementation.

## Reporting issues

Until/unless that changes, the only path for reporting issues is:

1. Run **Settings → Diagnostics → Copy Feedback Summary** (concise) or
   **Export Diagnostics** (detailed).
2. Open a GitHub issue and paste the relevant excerpt.

The diagnostics export deliberately excludes screenshots, cookies, page
content, and recording files. Review it before sharing.
