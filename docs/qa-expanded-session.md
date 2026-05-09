# Expanded Session QA

## Prerequisites

- macOS with Accessibility permission granted for every process identity in the
  shell-driven AppleScript launch chain: the terminal/editor that launches the
  command, the Node.js binary that runs this script, `/usr/bin/osascript`, and
  any wrapper or helper binary used to start the command. Run
  `make check-accessibility` first; if macOS denies access, the probe prints the
  exact Node.js `process.execPath` to add under System Settings > Privacy &
  Security > Accessibility. Quit and reopen the terminal/editor after changing
  Accessibility settings. To add `/usr/bin/osascript`, use the file picker
  shortcut `Cmd+Shift+G`, enter `/usr/bin/osascript`, and select it. The
  smoke Make targets also run this probe before packaging or launching the app,
  so missing permission should fail before the slower smoke setup starts.
- Google Chrome installed at `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`, or set `CHROME_PATH`.
- A packaged app bundle built with `make validate-package`.

## Automated Smoke

Run:

```sh
RUN_EXPANDED_INTERACTION_SMOKE=1 make smoke-expanded-interaction
```

To retain failure artifacts locally:

```sh
SMOKE_ARTIFACT_DIR=dist/gui-smoke-artifacts RUN_EXPANDED_INTERACTION_SMOKE=1 make smoke-expanded-interaction
```

To verify screenshot fallback mode:

```sh
RUN_EXPANDED_FALLBACK_SMOKE=1 make smoke-expanded-fallback
```

To verify live screencast recording and MP4 export without relying on
AppleScript toolbar traversal:

```sh
RUN_RECORDING_EXPORT_SMOKE=1 make smoke-recording-export
```

The smoke test launches Chrome with CDP, creates a temporary daemon `.session` file, opens the app directly into the expanded session view, and verifies:

- The expanded view reaches `Live screencast`.
- The screenshot surface, toolbar controls, metadata toggle, and interaction
  mode control are present in the accessibility tree.
- The screenshot surface has a usable size before and after window resize.
- Enabling interaction exposes the `Control mode` state.
- The browser surface updates while a page counter changes.
- Pointer click and wheel events reach the page.
- Click coordinates still work after resizing the app window.
- Text input and special keys reach the page through the expanded surface.
- The recording toggle is available in live screencast mode and captures raw
  JPEG frames plus `manifest.json` under `~/Downloads/PlaywrightDashboard Recordings`.
  After stopping a recording, the folder button should reveal the completed
  recording directory in Finder. The film button should export `recording.mp4`
  into the same directory without deleting the raw frames.
- When the browser changes during control mode without recent local input, the
  expanded view shows an `Agent active` warning badge.

The fallback smoke launches the same packaged app with a smoke-only flag that
forces the expanded view to skip `Page.startScreencast`. It verifies the
`Snapshot fallback` badge, the same structural controls, and the same
interaction path. Pixel-change detection is only required in live screencast
mode; fallback mode remains structural and event-driven.

The recording export smoke launches a temporary Chrome/CDP page, lets the app's
smoke-only runner capture live screencast frames through the same recording
writer and MP4 exporter used by the UI, and validates `manifest.json`,
`frame-000001.jpg`, and `recording.mp4` on disk.

## Expected UI

- The top-right badge should read `Live screencast`.
- If streaming fails, the badge should read `Snapshot fallback`; that is acceptable only when explicitly testing fallback behavior.
- The interaction badge should appear after enabling screenshot interaction.
- The recording badge should appear after starting a recording and disappear
  after stopping it.
- The `Agent active` badge may appear briefly if another client changes the
  page while interaction mode is set to Control.

## Manual Checks

1. Open a live Playwright session in the dashboard.
2. Open the expanded view.
3. Confirm the badge changes from `Snapshot refresh` to `Live screencast`.
4. Enable interaction and click a visible page control.
5. Type into a focused input, then press Backspace and Enter.
6. Resize the window and repeat the click.
7. Start recording, wait for several visible page changes, stop recording, and
   verify the recording directory contains JPEG frames and `manifest.json`.
   Export MP4, verify `recording.mp4` appears, and use the folder button to
   reveal the same directory in Finder.
8. While Control mode is enabled, change the page from another CDP client and
   confirm the `Agent active` badge appears briefly.
9. Leave the expanded view open for at least 30 seconds and confirm it does not fall back.

## Failure Capture

When `SMOKE_ARTIFACT_DIR` is set, the smoke test writes:

- `error.txt`
- `progress.log`
- `events.json`
- `ui-snapshot.txt`
- `surface-before.png` and `surface-after.png` when available

There is also a manual `GUI Smoke` GitHub Actions workflow that runs this smoke
test and uploads those artifacts. The main `CI` workflow can run the same
Chrome-backed checks on demand with its `gui_smoke_mode` input, and the weekly
scheduled CI run exercises both live and fallback modes. Pull request CI gates
only the non-live `visual-structure-smoke` subset documented in
`docs/qa-visual-snapshots.md`.

For manual failures, capture:

- the expanded-session badge text,
- whether the page still changes visually,
- the app console logs,
- the Chrome CDP port and session file contents.
