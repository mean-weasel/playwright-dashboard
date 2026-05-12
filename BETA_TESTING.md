# Playwright Dashboard Beta Testing

For a user-oriented walkthrough of Safe vs Control mode, common
workflows, and troubleshooting, see [`docs/user-guide.md`](docs/user-guide.md).
For the project's no-telemetry stance, see
[`docs/telemetry-policy.md`](docs/telemetry-policy.md).

## Install

1. Download the latest notarized zip from
   <https://github.com/mean-weasel/playwright-dashboard/releases/latest>.
2. Unzip `PlaywrightDashboard-v<version>-<build>.zip`.
3. Move `PlaywrightDashboard.app` to `~/Applications`.
4. Open the app. macOS should report it as a notarized Developer ID app.

## What To Try

- Start a few headed Playwright sessions with `playwright-cli`.
- Confirm the menu bar popover and dashboard discover active sessions.
- Open expanded views and check that screenshots or screencasts refresh.
- Leave Safe read-only mode enabled and confirm the app observes without
  closing sessions, cleaning stale sessions, opening CDP inspector, navigating
  pages, or forwarding browser input.
- Explicitly enable Control mode for a throwaway session and confirm navigation
  works only after that opt-in.

## Reporting Feedback

Include:

- macOS version and Mac model.
- Playwright Dashboard version and build from Settings.
- `playwright-cli --version`.
- What you expected, what happened, and whether Safe mode was enabled.
- A diagnostics export from Settings > Diagnostics > Export Diagnostics.

Diagnostics include local paths, ports, URLs, settings, and errors. They do not
include screenshots, cookies, page content, or recording files.

## Known Limitations

- The app observes local Playwright sessions created by `playwright-cli`; remote
  browsers and non-loopback CDP endpoints are intentionally rejected.
- Safe mode is the default. Browser control requires an explicit Control mode
  opt-in for each expanded session.
- Screenshot and screencast fidelity depends on the browser exposing a usable
  local CDP endpoint.
- Launch-at-login and Accessibility behavior can vary by macOS privacy settings;
  use diagnostics export when reporting those issues.
