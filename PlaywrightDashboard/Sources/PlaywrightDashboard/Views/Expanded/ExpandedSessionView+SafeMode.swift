import SwiftUI

struct SafeModeBlockedError: LocalizedError {
  var errorDescription: String? {
    "Safe mode is enabled. Browser navigation and input forwarding are disabled."
  }
}

extension ExpandedSessionView {
  var effectiveInteractionEnabled: Bool {
    interactionEnabled && !safeMode
  }

  var interactionModeBinding: Binding<Bool> {
    Binding(
      get: { interactionEnabled && !safeMode },
      set: { newValue in
        guard !safeMode else {
          interactionEnabled = false
          return
        }
        interactionEnabled = newValue
      }
    )
  }
}
