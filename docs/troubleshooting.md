# Troubleshooting

Start with the Makefile target that matches the failing area. The targets print
the most useful missing prerequisite or opt-in environment variable before
exiting.

## No Sessions Appear

- Confirm a Playwright daemon session exists under
  `~/Library/Caches/ms-playwright/daemon/<hash>/*.session`.
- Top-level `*.session` files are ignored; valid files live inside daemon hash
  directories.
- Directories with `user-data` in the name are ignored because they are browser
  profile directories.
- If the daemon directory does not exist, the app waits and rescans after it is
  created.
- Check whether the app shows session-file parse errors. Invalid JSON or missing
  required fields prevent a session from being added.

## `playwright-cli not found`

The app checks CLI availability and closes sessions through
`/usr/bin/env playwright-cli`.

- Verify `playwright-cli --version` works in the same environment that launches
  the app.
- If the app is launched from Finder or as a login item, remember that its `PATH`
  can differ from your interactive shell.
- Reopen the app after changing shell or login environment setup.

## CDP Port Is Missing Or Not Responding

Expanded session interaction needs a CDP port. The app reads it from
`browser.launchOptions.cdpPort` or `--remote-debugging-port=<port>` in the
session file.

- Inspect the session metadata panel for the CDP port.
- If the port is `0` or missing, start the Playwright session with CDP enabled.
- If the port exists but does not respond, confirm the browser process is still
  running and that the session file is not stale.
- Use `RUN_LIVE_CDP_SMOKE=1 make smoke-live-cdp` against a known live session to
  separate app UI issues from CDP connectivity issues.

## Expanded View Shows Snapshot Fallback

`Snapshot fallback` means live `Page.startScreencast` could not be used and the
view is polling screenshots instead.

- This is expected when running
  `RUN_EXPANDED_FALLBACK_SMOKE=1 make smoke-expanded-fallback`.
- For normal live smoke, expect the badge to reach `Live screencast`.
- Check whether the CDP port responds and whether Chrome is still alive.
- Capture `SMOKE_ARTIFACT_DIR=dist/gui-smoke-artifacts` when debugging GUI smoke
  failures.

## GUI Smoke Or Visual Snapshots Fail With Permission Errors

Run:

```sh
make check-accessibility
```

The expanded smoke and visual snapshot Make targets run this check before
package validation or app launch. A failure here means macOS denied the
AppleScript accessibility probe, not that the app failed to build.

Grant Accessibility permission under System Settings > Privacy & Security >
Accessibility to:

- the terminal or editor that launches the command,
- the Node.js binary printed by the accessibility check,
- `/usr/bin/osascript`,
- any wrapper or helper binary used by your environment.

Quit and reopen the terminal or editor after changing permissions. To add
`/usr/bin/osascript`, use `Cmd+Shift+G` in the file picker and enter
`/usr/bin/osascript`.

## GUI Smoke Exits Without Running

The smoke targets intentionally fail with exit code `2` until opted in:

```sh
RUN_GUI_SMOKE=1 make smoke-app
RUN_EXPANDED_INTERACTION_SMOKE=1 make smoke-expanded-interaction
RUN_EXPANDED_FALLBACK_SMOKE=1 make smoke-expanded-fallback
RUN_RECORDING_EXPORT_SMOKE=1 make smoke-recording-export
RUN_MULTI_SESSION_SMOKE=1 make smoke-multi-session
RUN_SAFE_MODE_OBSERVER_SMOKE=1 make smoke-safe-mode-observer
RUN_PLAYWRIGHT_CLI_MULTI_SMOKE=1 make smoke-playwright-cli-multi-session
RUN_LOGIN_ITEM_SMOKE=1 make smoke-login-item
RUN_LIVE_CDP_SMOKE=1 make smoke-live-cdp
```

Chrome is required for expanded-session and recording-export smoke. Set
`CHROME_PATH` if it is not at
`/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`.

## Package Or Codesign Fails

Run the full package validation target:

```sh
make validate-package
```

The target checks executable permissions, app icon generation, `Info.plist`
values, codesigning, zip contents, and the unzipped app. If no developer signing
identity is available, the Makefile uses ad-hoc signing. If codesign fails with a
specific identity, the Makefile reports the identity and falls back to ad-hoc
signing.

Use `make clean` to remove SwiftPM build output and `dist/` before rebuilding.

## Persistence Or Closed History Looks Wrong

The app stores session metadata with SwiftData. If persistence initialization
falls back internally, the app marks persistence as degraded and continues with a
fallback container.

- Try quitting and reopening the app.
- Clear closed session history from Settings if stale closed records are the
  problem.
- Use `make test` for model and session-management regressions before changing
  persistence code.

## Visual Snapshot Differences

Visual snapshot baseline comparison is a review signal, not a blocking image
diff. Exact PNG hashes can change with macOS rendering, window shadows, and live
browser content.

- Compare `dist/visual-snapshots/summary.md` and `manifest.json`.
- Treat `changed` as a prompt to inspect the PNGs manually.
- Regenerate a local baseline with `make visual-snapshot-baseline` when the
  visual change is intentional.
