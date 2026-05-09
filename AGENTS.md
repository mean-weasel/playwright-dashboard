# Agent Guide

## Project State

Playwright Dashboard is a native macOS menu bar app for discovering and observing
local `playwright-cli` browser sessions. The latest released build is `v0.1.2`,
signed, notarized, stapled, and verified by CI.

The app is ready for manual dogfooding on real Macs. Treat it as beta-quality:
safe for observing local sessions with Safe read-only mode enabled, but not yet
broad production software.

## Safety Model

- Safe read-only mode defaults on for new installs.
- Safe mode permits discovery, metadata, thumbnails/live frames, diagnostics,
  screenshot saving, and recording review.
- Safe mode blocks session close/cleanup, CDP inspector, navigation, and
  forwarded click/scroll/keyboard input.
- Browser control requires an explicit per-session opt-in from the expanded
  session view.
- CDP access is local-only; remote/non-loopback debugger endpoints are rejected.

Do not run live CDP or GUI smoke tests against a user's real sessions unless the
task explicitly asks for it.

## Common Commands

Run safe local checks from the repository root:

```sh
make lint
make test
make file-size
make validate-package
```

`make qa` runs lint, file-size checks, mockup checks, and unit tests.

Avoid `RUN_LIVE_CDP_SMOKE=1 make smoke-live-cdp` unless intentionally testing a
real Playwright/CDP browser session.

## Manual Use

Install the current notarized app from:
<https://github.com/neonwatty/playwright-dashboard/releases/latest>

Start headed sessions with `playwright-cli`; the app watches
`~/Library/Caches/ms-playwright/daemon` for nested `*.session` files. Keep Safe
mode enabled while observing active work.

For troubleshooting, use Settings > Diagnostics:

- Copy Feedback Summary for concise app/environment context.
- Copy App Diagnostics or Export Diagnostics for detailed local state.

Diagnostics include local paths, ports, URLs, settings, and errors. They exclude
screenshots, cookies, page content, and recording files.

## CI And Release

Required PR validation includes build, lint, file-size, package, unit tests,
coverage, structural UI smoke, Safe-mode observer smoke, and real
`playwright-cli` multi-session smoke.

Release artifacts are produced by the `Release macOS App` workflow from `v*`
tags or manual dispatch. Apple signing/notarization secrets are already
configured in GitHub; local certificates are in
`~/Desktop/apple-developer-certificates` on the Mac mini.

## Current Next Work

After manual use starts, prioritize reliability findings over more beta process:
watcher stability, CDP reconnect behavior, sleep/wake behavior, browser restarts,
many-session handling, and UI friction discovered during real workflows.
