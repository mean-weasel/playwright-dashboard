import SwiftUI

struct SettingsView: View {
  @AppStorage("staleThresholdSeconds") private var staleThresholdSeconds = 120
  @AppStorage("launchAtLogin") private var launchAtLogin = false

  private let thresholdOptions: [(label: String, seconds: Int)] = [
    ("1 minute", 60),
    ("2 minutes", 120),
    ("5 minutes", 300),
    ("10 minutes", 600),
    ("Never", 0),
  ]

  var body: some View {
    Form {
      Picker("Mark sessions stale after", selection: $staleThresholdSeconds) {
        ForEach(thresholdOptions, id: \.seconds) { option in
          Text(option.label).tag(option.seconds)
        }
      }

      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
          if enabled {
            LaunchAtLoginManager.enable()
          } else {
            LaunchAtLoginManager.disable()
          }
        }
    }
    .formStyle(.grouped)
    .frame(width: 350)
    .onAppear {
      // Sync toggle with actual plist state on disk
      launchAtLogin = LaunchAtLoginManager.isEnabled
    }
  }
}
