# Agent Guide

## Project State

Playwright Dashboard is a native macOS menu bar app for discovering and observing
local `playwright-cli` browser sessions. The latest released build is `v0.1.2`,
signed, notarized, stapled, and verified by CI.

The required PR check set covers lint, build, unit tests, coverage floor,
file-size, mockup checks, package validation, structural UI smoke,
Safe-mode observer smoke, real `playwright-cli` multi-session smoke,
dashboard-actions smoke (rename / reorder / persistence / close / stale /
search / closed-history filter), multi-target smoke (tab switching),
recording smoke (MP4 export against a CLI session), interaction smoke
(pointer / wheel / keyboard forwarding against a CLI session), and the
reliability smoke (Chrome kill, browser restart, sleep/wake CDP
reconnect). Local-only telemetry by design — see
[`docs/telemetry-policy.md`](docs/telemetry-policy.md).

The app is ready for use on real Macs with the safety boundaries
documented in [`docs/user-guide.md`](docs/user-guide.md). Safe read-only
mode is the default and is the right posture for observing sessions
you don't own.

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
<https://github.com/mean-weasel/playwright-dashboard/releases/latest>

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
