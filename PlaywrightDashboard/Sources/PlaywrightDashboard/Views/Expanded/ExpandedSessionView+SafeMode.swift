import SwiftUI

struct SafeModeBlockedError: LocalizedError {
  var errorDescription: String? {
    "Safe mode is enabled. Browser navigation and input forwarding are disabled."
  }
}

extension ExpandedSessionView {
  func initializeInteractionState() {
    interactionEnabled = appState.isBrowserControlAuthorized(for: session)
  }

  var sessionSafeModeEnabled: Bool {
    safeMode && !appState.isBrowserControlAuthorized(for: session)
  }

  var effectiveInteractionEnabled: Bool {
    interactionEnabled && appState.isBrowserControlAuthorized(for: session)
  }

  var interactionModeBinding: Binding<Bool> {
    Binding(
      get: { interactionEnabled && appState.isBrowserControlAuthorized(for: session) },
      set: { newValue in
        if newValue {
          appState.authorizeBrowserControl(for: session)
          interactionEnabled = true
        } else {
          appState.revokeBrowserControl(for: session)
          interactionEnabled = false
        }
      }
    )
  }

  func enableControlMode() {
    appState.authorizeBrowserControl(for: session)
    interactionEnabled = true
  }

  func returnToSafeMode() {
    appState.revokeBrowserControl(for: session)
    interactionEnabled = false
    safeMode = true
  }
}
