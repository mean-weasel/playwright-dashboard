import SwiftUI

extension SessionInfoBar {
  var controlModeControl: some View {
    Group {
      if safeModeEnabled {
        Button {
          showsControlModeConfirmation = true
        } label: {
          Label("Enable Control", systemImage: "cursorarrow.click.2")
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(session.cdpPort <= 0 || session.lastScreenshot == nil)
        .accessibilityIdentifier("expanded-enable-control-mode")
        .help(controlModeOptInHelp)
      } else {
        HStack(spacing: 8) {
          Picker(
            "Interaction mode",
            selection: Binding(
              get: { interactionEnabled },
              set: { interactionEnabled = $0 }
            )
          ) {
            Label("View", systemImage: "eye").tag(false)
            Label("Control", systemImage: "cursorarrow.click.2").tag(true)
          }
          .pickerStyle(.segmented)
          .controlSize(.small)
          .frame(width: 150)
          .disabled(session.cdpPort <= 0 || session.lastScreenshot == nil)
          .accessibilityLabel("Browser interaction mode")
          .accessibilityIdentifier("expanded-interaction-mode")
          .help(interactionHelp)

          Button {
            returnToSafeMode()
          } label: {
            Image(systemName: "lock.shield")
              .font(.body)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Return to Safe Mode")
          .accessibilityIdentifier("expanded-return-to-safe-mode")
          .help("Re-enable Safe read-only mode and stop forwarding browser input.")
        }
      }
    }
  }

  var controlModeOptInHelp: String {
    if session.cdpPort <= 0 {
      return "Control mode requires a CDP port."
    }
    if session.lastScreenshot == nil {
      return "Control mode is available after the first browser frame."
    }
    return "Confirm before forwarding navigation and input to this browser session."
  }

  func enableControlMode() {
    appState.dismissOpenURLError()
    interactionEnabled = true
    onEnableControlMode()
    modeStatusMessage = "Control mode enabled. Browser input can reach this session."
  }

  func returnToSafeMode() {
    appState.dismissOpenURLError()
    interactionEnabled = false
    onReturnToSafeMode()
    modeStatusMessage =
      "Safe mode restored for this session. Navigation and input forwarding are disabled."
  }
}
