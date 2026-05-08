# Changelog

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
