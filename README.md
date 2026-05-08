# Playwright Dashboard

Playwright Dashboard is a native macOS menu bar app for discovering, monitoring,
and interacting with local Playwright browser sessions. It watches
`~/Library/Caches/ms-playwright/daemon` for `*.session` files created by
`playwright-cli`, shows active and closed sessions in a dashboard, and can open an
expanded session view backed by CDP screencast or screenshot fallback.

## Requirements

- macOS 15 or newer.
- Xcode 16.3 or a compatible Swift 6 toolchain.
- `swift-format` for linting. `make lint` uses `swift-format` from `PATH`,
  `xcrun --find swift-format`, or bootstraps a pinned repo-local copy under
  `PlaywrightDashboard/.build/tools` when neither is installed.
- `playwright-cli` on `PATH` for CLI availability checks and session close
  commands.
- Google Chrome for live CDP and GUI smoke tests. The default path is
  `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`; set
  `CHROME_PATH` when using another location.

## Download

The latest notarized macOS build is available from
[GitHub Releases](https://github.com/neonwatty/playwright-dashboard/releases/latest).

Current release:

- `PlaywrightDashboard-v0.1.0-2.zip`
- SHA-256:
  `a310178b71b73c07d3c9aef423662f3ea368f601f5d5845beccbc92c8d0dc6e6`

The release artifact is Developer ID signed, notarized, stapled, and verified
with Gatekeeper.

## Build And Test

Use the Makefile from the repository root:

```sh
make build
make test
make coverage
make lint
make qa
```

`make qa` runs lint, file-size checks, mockup checks, and unit tests. Build output
is under `PlaywrightDashboard/.build`. Coverage prints the generated code
coverage JSON path.

Set `SWIFT_FORMAT=/path/to/swift-format` to force a specific formatter binary,
or `SWIFT_FORMAT_TAG=<tag>` to change the pinned repo-local bootstrap tag.

## Package And Install

Create and validate a signed app bundle:

```sh
make validate-package
```

This builds `dist/PlaywrightDashboard.app`, signs it with the first available
codesigning identity or ad-hoc signing, validates `Info.plist`, verifies the
signature, and creates `dist/PlaywrightDashboard.zip`.

Create a local beta artifact after the standard QA gate:

```sh
make beta-release APP_VERSION=0.1.0 BUILD_NUMBER=1
```

For a notarized external beta, configure an `xcrun notarytool` keychain profile
and use a Developer ID Application certificate:

```sh
xcrun notarytool store-credentials playwright-dashboard \
  --team-id 3CDYUL285D

make notarized-release \
  APP_VERSION=0.1.0 \
  BUILD_NUMBER=1 \
  NOTARY_PROFILE=playwright-dashboard
```

Set `DEVELOPER_ID_IDENTITY` when the default Developer ID certificate selection
is not the one you want. The Developer ID Application certificate must be
installed in the login keychain before this target can sign the app for
notarization.

CI notarized releases use the `Release macOS App` workflow and the
`apple-signing` GitHub environment. Configure these repository or environment
secrets:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`.
- `APPLE_TEAM_ID`: Apple Developer Team ID, for example `3CDYUL285D`.
- `APPLE_API_KEY_BASE64`: base64-encoded App Store Connect API key `.p8`.
- `APPLE_API_KEY_ID`: App Store Connect API key ID.
- `APPLE_API_ISSUER_ID`: App Store Connect issuer ID.

Run the workflow manually with a version and optional build number, or push a
`v*` tag to build, sign, notarize, staple, verify, and upload
`PlaywrightDashboard-v<version>-<build>.zip`.

Install to `~/Applications` and launch it:

```sh
make install
```

The install target copies the packaged app to
`~/Applications/PlaywrightDashboard.app` and opens it.

## Running The App

After launch, Playwright Dashboard appears in the macOS menu bar. Use the menu
bar popover for a compact session list, then open the dashboard window for the
grid, settings, closed history, and expanded session view.

Session discovery is local-only:

- The app watches `~/Library/Caches/ms-playwright/daemon`.
- It scans nested daemon hash directories for `*.session` files.
- It ignores `user-data` directories and top-level `*.session` files.
- CDP ports are read from modern `browser.launchOptions.cdpPort` fields or
  legacy `--remote-debugging-port=<port>` launch args.

If no daemon directory exists yet, the watcher waits and retries until
Playwright creates one.

Enable Safe read-only mode in Settings when observing active sessions that
should not be disrupted. It keeps discovery, thumbnails, live frames, metadata,
and screenshot saving available while disabling session close/cleanup, CDP
inspector access, browser navigation, and forwarded click/scroll/keyboard input.
When enabled, the dashboard, sidebar, menubar popover, and expanded session
toolbar show a Safe badge.

## Permissions

Normal app use does not require the GUI smoke-test Accessibility setup. GUI QA
and visual snapshot commands do, because they drive the packaged app with
AppleScript and Node.js.

Before GUI QA, grant Accessibility permission to every process identity in the
launch chain:

- the terminal or editor that launches the command,
- the Node.js binary printed by `make check-accessibility`,
- `/usr/bin/osascript`,
- any wrapper or helper binary used by your environment.

Run:

```sh
make check-accessibility
```

If access is denied, add the listed apps or binaries under System Settings >
Privacy & Security > Accessibility, then quit and reopen the terminal or editor.
To add `/usr/bin/osascript`, use `Cmd+Shift+G` in the file picker and enter
`/usr/bin/osascript`.

## Visual And GUI QA

Visual snapshots capture deterministic states from the packaged macOS app:

```sh
make visual-snapshots
make visual-snapshot-baseline
make visual-snapshot-compare
```

Snapshots and `manifest.json` are written to `dist/visual-snapshots` by default.
Baseline comparison is non-blocking and reports `unchanged`, `changed`, or
`missing`.

Expanded-session GUI smoke tests are opt-in:

```sh
RUN_EXPANDED_INTERACTION_SMOKE=1 make smoke-expanded-interaction
RUN_EXPANDED_FALLBACK_SMOKE=1 make smoke-expanded-fallback
RUN_RECORDING_EXPORT_SMOKE=1 make smoke-recording-export
```

To keep failure artifacts:

```sh
SMOKE_ARTIFACT_DIR=dist/gui-smoke-artifacts \
RUN_EXPANDED_INTERACTION_SMOKE=1 \
make smoke-expanded-interaction
```

For more detail, see `docs/development.md`, `docs/troubleshooting.md`,
`docs/qa-expanded-session.md`, and `docs/qa-visual-snapshots.md`.
