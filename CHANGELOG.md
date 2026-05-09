# Changelog

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
