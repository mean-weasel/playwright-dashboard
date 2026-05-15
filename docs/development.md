# Development

This repo builds a Swift Package executable into a macOS app bundle. Run all
commands below from the repository root.

## Common Commands

```sh
make build              # swift build -c release
make test               # swift test
make coverage           # swift test --enable-code-coverage
make lint               # swift-format lint
make format             # swift-format format --in-place
make file-size          # fail Swift source files over 300 lines
make mockups            # verify mockup HTML files are present
make qa                 # lint, file-size, mockups, test
make clean              # swift package clean and remove dist/
```

Use `CONFIGURATION=debug make build` when you need a debug Swift build.
`make lint` and `make format` run through `scripts/swift_format_tool.sh`. The
wrapper uses `SWIFT_FORMAT` when provided, then `swift-format` from `PATH`, then
`xcrun --find swift-format`, and finally bootstraps a pinned copy from
`swiftlang/swift-format` into `PlaywrightDashboard/.build/tools`. Override the
pinned tag with `SWIFT_FORMAT_TAG=<tag>` when the Swift toolchain changes.

## Package Workflow

```sh
make package
make validate-package
make install
```

`make package` builds `dist/PlaywrightDashboard.app`, generates the app icon,
writes `Info.plist`, signs the bundle, and creates `dist/PlaywrightDashboard.zip`.
`make validate-package` verifies bundle contents, plist values, codesigning, and
the zipped app. `make install` copies the app to
`~/Applications/PlaywrightDashboard.app` and opens it.

Codesigning uses the first available developer signing identity. If none is
found, the Makefile falls back to ad-hoc signing.

## CI Signing And Notarization

The `Release macOS App` GitHub Actions workflow signs and notarizes the app with
Developer ID credentials. It runs manually from `workflow_dispatch` or
automatically for `v*` tags, and uses the `apple-signing` environment.

Required secrets:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_API_KEY_BASE64`: base64-encoded App Store Connect API key `.p8`.
- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID.

The workflow imports the certificate into a temporary keychain, runs
`make developer-id-package`, submits `dist/PlaywrightDashboard.zip` to
notarization, staples the accepted ticket to `dist/PlaywrightDashboard.app`,
re-creates the zip, verifies the bundle version and signature, and uploads the
zip as an artifact. For a tag run, it also uploads the zip to the matching
GitHub Release.

Use the `Notary Status` workflow with a submission ID when you need to inspect a
slow or failed Apple notarization outside the release job logs.

### Recovering from a slow notarization

Apple notarization sometimes stays in `In Progress` for hours, even when the
submission is ultimately accepted. The `Release macOS App` workflow guards
against losing a valid release candidate in two ways:

1. Right after signing, the workflow uploads the pre-staple
   `dist/PlaywrightDashboard.zip` plus a `release-metadata.json` sidecar
   (version, build number, intended artifact name, source run ID) as the
   `signed-app-prestaple` artifact on the same run. This artifact survives a
   failed or timed-out notarization step for the 30-day retention window.
2. When notarization times out without an `Accepted`, `Invalid`, or `Rejected`
   verdict, the workflow fails with a `Notarization` section in the run
   summary that includes the submission ID, the source run ID, and explicit
   recovery instructions. `Invalid` and `Rejected` still fail loudly with the
   notary log — those are not recoverable by waiting longer.

To recover:

1. Watch `Notary Status` until the original submission reports `Accepted`.
2. Manually dispatch `Notary Complete` with:
   - `source_run_id`: the failing release run's ID (from the Recovery section).
   - `submission_id`: the same submission ID.
   - `release_tag` (optional): the `v*` tag the original release was for, if any.

`Notary Complete` re-confirms `Accepted`, downloads the pre-staple artifact,
staples the ticket, re-zips, verifies (Gatekeeper, codesign, launch smoke),
uploads the final release artifact, and — if a tag was provided — uploads to
the corresponding GitHub Release. The original signing run does not need to be
re-run.

## Session Discovery Model

The app discovers sessions from the Playwright daemon cache:

```text
~/Library/Caches/ms-playwright/daemon/<hash>/*.session
```

The watcher performs an initial scan, then uses FSEvents with a short debounce.
If the daemon directory does not exist yet, it polls every two seconds until it
appears. The session parser expects JSON with `name`, `version`, `timestamp`,
`socketPath`, `workspaceDir`, `cli`, and `browser` fields. The CDP port comes
from `browser.launchOptions.cdpPort` or a
`--remote-debugging-port=<port>` launch arg.

Closed sessions remain in the dashboard history until cleared or removed by the
configured retention behavior.

## Live CDP Checks

The live CDP test target is disabled unless explicitly opted in:

```sh
RUN_LIVE_CDP_SMOKE=1 make smoke-live-cdp
```

`make smoke-live-cdp` uses `LIVE_CDP_PORT` when set. Otherwise it runs
`scripts/discover_live_cdp_port.swift` to find a port from current daemon
session files. Add `RUN_LIVE_CDP_INTERACTION_SMOKE=1` to include interaction
coverage.

## GUI Smoke And Visual QA

Always build and validate the package first, or use targets that depend on
`validate-package`.

```sh
make check-accessibility
RUN_EXPANDED_INTERACTION_SMOKE=1 make smoke-expanded-interaction
RUN_EXPANDED_FALLBACK_SMOKE=1 make smoke-expanded-fallback
RUN_RECORDING_EXPORT_SMOKE=1 make smoke-recording-export
RUN_SAFE_MODE_OBSERVER_SMOKE=1 make smoke-safe-mode-observer
RUN_PLAYWRIGHT_CLI_MULTI_SMOKE=1 make smoke-playwright-cli-multi-session
RUN_PLAYWRIGHT_CLI_DASHBOARD_ACTIONS_SMOKE=1 make smoke-playwright-cli-dashboard-actions
RUN_REALISTIC_E2E_SMOKE=1 make smoke-realistic-e2e
VISUAL_SNAPSHOT_DIR=dist/visual-snapshots make visual-snapshots
```

The dashboard-actions smoke boots two real `playwright-cli` sessions, launches
the packaged app with smoke-only launch arguments
(`--smoke-rename-session-id` / `--smoke-rename-to` and
`--smoke-mark-session-closed-id` / `--smoke-dashboard-filter-closed`), and
asserts the resulting `dashboard-ready.json` readiness payload — covering the
rename round-trip and the closed-history filter without scraping any UI.

The reliability smoke covers two of the three failure modes called out in
`AGENTS.md`:

- **Chrome killed mid-session** (Phase 1) — `kill -9` the daemon-spawned
  Chrome and assert the dashboard reflects the session as closed within
  `RELIABILITY_KILL_SLA_MS` (default 30 s).
- **Browser restart / rediscovery** (Phase 2) — SIGKILL the
  `playwright-cli` daemon, force-remove its socket and `.session` files,
  then reopen with the same session id against the same long-lived
  dashboard launch. Asserts rediscovery within
  `RELIABILITY_RESTART_SLA_MS` (default 60 s). Note the smoke's session
  ids are intentionally short (`rk-<pid>` / `rr-<pid>`) so the daemon's
  socket path stays under macOS's 104-byte `sun_path` limit — longer ids
  push the path past 104 bytes on `macos-15` runners, the kernel silently
  truncates the bound path, and the next bind() collides with the
  truncated file → `EADDRINUSE`. Likely worth filing upstream with
  `@playwright/cli` so `makeSocketPath` errors out instead of silently
  producing a too-long path.

- **Sleep/wake CDP reconnect** (Phase 3) — `pmset sleepnow` needs root and
  the runner host does not actually suspend, so the smoke simulates sleep
  by `SIGSTOP`ping Chrome's main process. Chrome's CDP TCP server lives
  in that process, so a stopped Chrome looks exactly like a sleeping
  device from the dashboard: the WebSocket goes silent. After
  `RELIABILITY_SLEEP_DURATION_MS` (default 12 s) the smoke sends
  `SIGCONT` and asserts the dashboard exits the disconnected state within
  `RELIABILITY_WAKE_RECOVERY_SLA_MS` (default 30 s) — either reconnecting
  screencast (`liveScreencast`) or falling back to snapshot polling
  (`snapshotFallback`), but not stuck in `connectionLost`.

```sh
RUN_RELIABILITY_SMOKE=1 make smoke-reliability
```

The many-sessions stress smoke is opt-in (not in `smoke-all` or the required
CI gate). It boots twelve concurrent `playwright-cli` sessions and verifies
that the dashboard discovers all of them within an SLA, each session's
expanded view opens without hanging, closing every session returns the
dashboard to no-active state within an SLA, and the dashboard process's
RSS+CPU stay within a reasonable cap. Tunable via `MANY_SESSION_COUNT`,
`MANY_SESSION_DISCOVERY_SLA_MS`, `MANY_SESSION_CLEANUP_SLA_MS`, and
`MANY_SESSION_EXPANDED_TIMEOUT_MS`. In CI it runs only via the `many` (or
`all`) option of the `gui_smoke_mode` workflow_dispatch input.

```sh
RUN_MANY_SESSION_SMOKE=1 make smoke-many-sessions
```

The realistic E2E/demo smoke uses the static Operator Workbench fixture in
`fixtures/e2e-apps/operator-workbench`. It opens an isolated real
`playwright-cli` Chrome session, launches the packaged app in Safe mode against
an isolated daemon directory, captures Dashboard artifacts, and drives realistic
fixture route changes. It is intended as local proof and future docs-media
source material before becoming a required CI gate.

```sh
RUN_REALISTIC_E2E_SMOKE=1 SMOKE_ARTIFACT_DIR=dist/realistic-e2e-artifacts make smoke-realistic-e2e
DEMO_MEDIA_FROM_EXISTING=1 make demo-media
```

`make smoke-realistic-e2e` writes `progress.log`, `expanded-ready.json`,
`ui-snapshot.txt`, `scenario.json`, and `dashboard-window.png` to
`SMOKE_ARTIFACT_DIR` (default `dist/realistic-e2e-artifacts`). `make demo-media`
promotes those artifacts into `dist/docs-media/operator-workbench` with
`manifest.json` and `summary.md`; see `docs/realistic-e2e-media-plan.md`.
Generated media under `dist/` is ignored and should not be committed without
explicit approval.

To mirror the required CI surface locally with one target, use `make smoke-all`:

```sh
make smoke-all
```

`smoke-all` runs `make check-accessibility` once, then `qa`, `validate-package`,
`visual-structure-smoke`, `smoke-safe-mode-observer`, and
`smoke-playwright-cli-multi-session`. It propagates `SKIP_ACCESSIBILITY_CHECK=1`,
`SMOKE_REUSE_PACKAGE=1`, and `RUN_ALL_SMOKES=1` to the sub-makes so the
accessibility probe and package build only happen once and the per-smoke env
gates are satisfied without enumerating them. `RUN_ALL_SMOKES=1` is also
accepted as an alternative to the individual `RUN_*_SMOKE=1` flag on every
gated smoke target. Use `make smoke-all-extended` to also run the exploratory
expanded-session, fallback, recording, and multi-session smokes. Use
`SMOKE_ALL_DRY_RUN=1 make smoke-all` (or `smoke-all-extended`) to print the
planned steps without running them.

GUI smoke and visual snapshot tests require Accessibility permission for the
terminal/editor, Node.js, `/usr/bin/osascript`, and any wrapper process. They
also require Chrome, using `CHROME_PATH` when it is not installed at the default
path.
The Safe-mode observer smoke verifies blocked close/cleanup/navigation/CDP
inspector/input behavior. The Playwright CLI multi-session smoke verifies the
real `playwright-cli` session discovery path. The recording export smoke
launches the packaged app and Chrome/CDP, but avoids AppleScript UI traversal by
using the app's smoke-only recording runner.

### Smoke Retry Policy

Each Chrome-driven GUI smoke target (`smoke-expanded-interaction`,
`smoke-expanded-fallback`, `smoke-recording-export`, `smoke-multi-session`,
`smoke-safe-mode-observer`, `smoke-playwright-cli-multi-session`) is invoked
through `scripts/run_smoke_with_retry.mjs`. Set `SMOKE_RETRY_COUNT=N` to allow
up to `N` retries on top of the initial attempt. The wrapper records each run
in `dist/smoke-results.json` and, between attempts, kills any running
`PlaywrightDashboard` process before re-running so the smoke script's own
preflight starts from a clean slate.

Defaults:

- **Locally:** `SMOKE_RETRY_COUNT` is unset (0), so smokes run once and fail on
  the first hiccup. Run with `SMOKE_RETRY_COUNT=1 make smoke-...` when
  investigating an intermittent failure.
- **CI:** the workflow sets `SMOKE_RETRY_COUNT=1`, so a single transient
  failure does not fail the gate. Records and the retry flag are uploaded as
  `smoke-results-<job>` artifacts and aggregated by the `CI Gate` job into a
  **Smoke Flake Summary** in the run summary.

To disable retries in CI while keeping the rest of the policy, set
`SMOKE_RETRY_COUNT=0` in the relevant job env.

Visual snapshots are artifact-only. Baseline comparison is intentionally
non-blocking:

```sh
make visual-snapshot-baseline
make visual-snapshot-compare
```

Use `VISUAL_SNAPSHOT_BASELINE_DIR` and `VISUAL_SNAPSHOT_COMPARE_DIR` to compare
against a saved artifact set.

## CI Workflow

The main `CI` workflow runs on pull requests to `main`, pushes to `main`,
merge queue, a weekly schedule, and manual dispatch. Required jobs cover lint,
build, unit tests, coverage, file-size checks, mockup validation, and package
validation. CI uploads build logs, test logs, coverage JSON, and the packaged app
zip.

### Coverage Floor

The `coverage` job in `.github/workflows/ci.yml` enforces two floors:

- `SOURCE_COVERAGE_FLOOR` (default `30`): the aggregate line coverage of
  everything under `Sources/PlaywrightDashboard/` must be at least this
  percentage. If it drops below, the job fails. Files whose basename starts
  with `Smoke` (test-only fixtures, launch-arg parsers, and readiness
  reporters exercised by GUI smokes rather than unit tests) are excluded
  from the aggregate so PRs that add smoke infrastructure don't get
  penalized for unit-test coverage they wouldn't have anyway.
- `PER_FILE_COVERAGE_FLOOR` (default `10`): every file under
  `Sources/PlaywrightDashboard/Services/` or `Sources/PlaywrightDashboard/Models/`
  with at least `PER_FILE_FLOOR_MIN_LINES` (default `15`) executable lines must
  be covered above this percentage. Files smaller than the threshold are
  exempt, and View files are intentionally not subject to the per-file floor
  because UI code is mostly exercised by GUI smokes.

The initial values were picked from the current baseline (source coverage was
30.15% when the floor was introduced). Raise them in follow-up PRs as tests
fill in. Set the env knobs in the workflow's `coverage` job to change the
thresholds; the job summary prints both the current values and any
violations.

Pull request CI uses path filtering. Documentation-only PRs can skip code jobs;
changes under `PlaywrightDashboard/**`, `Makefile`, `scripts/**`, `.github/**`,
or mockup HTML files run the full code path.

Pull request, push, merge queue, scheduled, and manual CI run the Safe-mode
observer smoke and real Playwright CLI multi-session smoke when code paths
change. Scheduled CI also runs the exploratory expanded-view GUI smoke jobs, but
those jobs are non-blocking because macOS runner input delivery can be flaky;
manual dispatch keeps those optional smoke jobs strict. The separate `GUI Smoke`
workflow can manually run the full GUI smoke suite and upload artifacts.

The realistic E2E/demo smoke has a manual `GUI Smoke` mode and runs on scheduled
CI as non-blocking telemetry. Promote it in stages:

1. Done: add it to the manual `GUI Smoke` workflow with artifact upload.
2. In progress: run it on scheduled CI as non-blocking for at least one week.
3. Make it required only after the failure rate is comparable to the existing
   required Playwright CLI smoke jobs and artifact output is useful for
   debugging failures.

Do not use the realistic smoke to implement or deploy GitHub Pages. Pages work
belongs in a later tranche after the media pipeline is stable.

## Local PR Checklist

Before opening a code PR, run:

```sh
make qa
make validate-package
```

For UI, expanded-session, or settings work, also run the relevant GUI or visual
QA target and attach the produced artifacts when reviewing visual changes.
