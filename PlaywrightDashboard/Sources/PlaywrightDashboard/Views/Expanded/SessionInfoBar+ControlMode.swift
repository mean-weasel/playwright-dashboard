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
    return "Confirm before disabling Safe read-only mode and forwarding input to the browser."
  }

  func enableControlMode() {
    appState.dismissOpenURLError()
    interactionEnabled = true
    onEnableControlMode()
  }
}
