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
  shortcut `Cmd+Shift+G`, enter `/usr/bin/osascript`, and select it.
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

The smoke test launches Chrome with CDP, creates a temporary daemon `.session` file, opens the app directly into the expanded session view, and verifies:

- The expanded view reaches `Live screencast`.
- The browser surface updates while a page counter changes.
- Pointer click and wheel events reach the page.
- Click coordinates still work after resizing the app window.
- Text input and special keys reach the page through the expanded surface.

The fallback smoke launches the same packaged app with a smoke-only flag that forces the expanded view to skip `Page.startScreencast`. It verifies the `Snapshot fallback` badge and the same interaction path.

## Expected UI

- The top-right badge should read `Live screencast`.
- If streaming fails, the badge should read `Snapshot fallback`; that is acceptable only when explicitly testing fallback behavior.
- The interaction badge should appear after enabling screenshot interaction.

## Manual Checks

1. Open a live Playwright session in the dashboard.
2. Open the expanded view.
3. Confirm the badge changes from `Snapshot refresh` to `Live screencast`.
4. Enable interaction and click a visible page control.
5. Type into a focused input, then press Backspace and Enter.
6. Resize the window and repeat the click.
7. Leave the expanded view open for at least 30 seconds and confirm it does not fall back.

## Failure Capture

When `SMOKE_ARTIFACT_DIR` is set, the smoke test writes:

- `error.txt`
- `events.json`
- `ui-snapshot.txt`
- `surface-before.png` and `surface-after.png` when available

There is also a manual `GUI Smoke` GitHub Actions workflow that runs this smoke test and uploads those artifacts.
The main `CI` workflow can run the same checks on demand with its `gui_smoke_mode` input, and the weekly scheduled CI run exercises both live and fallback modes.

For manual failures, capture:

- the expanded-session badge text,
- whether the page still changes visually,
- the app console logs,
- the Chrome CDP port and session file contents.
