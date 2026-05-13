# Changelog

## 0.1.3 - 2026-05-12

- Documented the no-telemetry stance in `docs/telemetry-policy.md` and added a
  user-facing walkthrough in `docs/user-guide.md`.
- Menu bar popover gains a Check for Updates affordance that opens the GitHub
  Releases page in the user's default browser.
- SessionFileScanner skips symbolic links before reading daemon session files,
  hardening the watcher against malicious symlink injection.
- Periodic session sync now runs as a single tracked Task with an immediate
  first iteration; persistence-recovery work is tracked and replaces in-flight
  retries on each save failure.
- DaemonWatcher uses a generation counter so off-MainActor timer and FSEvents
  hops bail out when `stop()` has been called.
- Catastrophic SwiftData initialization failures (persistent store and
  in-memory fallback both failing) now surface via NSAlert and exit cleanly
  instead of `fatalError`. Removes the only `fatalError` in `Sources/`.
- CDPPageConnection logs swallowed `Page.stopScreencast` errors during
  teardown instead of bare `try?`.

## 0.1.2 - 2026-05-09

- GUI smoke tests now use app-emitted readiness artifacts instead of fragile
  macOS Accessibility window enumeration for menu-bar-first launch paths.
- Safe observer and real Playwright CLI multi-session smokes verify dashboard
  discovery, expanded-session readiness, Safe mode non-navigation, and Control
  mode navigation against signed/notarized app candidates.
- Release launch smoke is more robust when LaunchServices is slow to expose the
  app process.
- Beta safety surfaces are hardened with additional validation around session
  files, CDP endpoints, WebSocket hosts, and session termination.

## 0.1.1 - 2026-05-08

- Safe read-only mode now defaults on for new installs.
- Normal app launches no longer overwrite persisted Safe mode settings from
  absent smoke-test flags.
- Expanded session control now requires an explicit confirmation before Safe mode
  is disabled.
- Expanded sessions include a Return to Safe Mode action that immediately stops
  input forwarding and blocks navigation again.
- Safe mode disables session close/cleanup, CDP inspector access, browser
  navigation, and forwarded click/scroll/keyboard input while preserving
  observation features.

## 0.1.0 - 2026-05-08

- Initial signed and notarized macOS release.
