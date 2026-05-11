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
VISUAL_SNAPSHOT_DIR=dist/visual-snapshots make visual-snapshots
```

GUI smoke and visual snapshot tests require Accessibility permission for the
terminal/editor, Node.js, `/usr/bin/osascript`, and any wrapper process. They
also require Chrome, using `CHROME_PATH` when it is not installed at the default
path.
The Safe-mode observer smoke verifies blocked close/cleanup/navigation/CDP
inspector/input behavior. The Playwright CLI multi-session smoke verifies the
real `playwright-cli` session discovery path. The recording export smoke
launches the packaged app and Chrome/CDP, but avoids AppleScript UI traversal by
using the app's smoke-only recording runner.

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

Pull request CI uses path filtering. Documentation-only PRs can skip code jobs;
changes under `PlaywrightDashboard/**`, `Makefile`, `scripts/**`, `.github/**`,
or mockup HTML files run the full code path.

Pull request, push, merge queue, scheduled, and manual CI run the Safe-mode
observer smoke and real Playwright CLI multi-session smoke when code paths
change. Scheduled CI also runs the exploratory expanded-view GUI smoke jobs, but
those jobs are non-blocking because macOS runner input delivery can be flaky;
manual dispatch keeps those optional smoke jobs strict. The separate `GUI Smoke`
workflow can manually run the full GUI smoke suite and upload artifacts.

## Local PR Checklist

Before opening a code PR, run:

```sh
make qa
make validate-package
```

For UI, expanded-session, or settings work, also run the relevant GUI or visual
QA target and attach the produced artifacts when reviewing visual changes.
