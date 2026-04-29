import Testing

@testable import PlaywrightDashboard

@Suite("LaunchAtLoginManager")
struct LaunchAtLoginManagerTests {

  @Test("Legacy LaunchAgent plist points at executable")
  func legacyPlist() {
    let plist = LaunchAtLoginManager.legacyLaunchAgentPlist(
      executablePath: "/Applications/PlaywrightDashboard.app/Contents/MacOS/PlaywrightDashboard")

    #expect(plist["Label"] as? String == "com.neonwatty.PlaywrightDashboard")
    #expect(
      plist["ProgramArguments"] as? [String]
        == ["/Applications/PlaywrightDashboard.app/Contents/MacOS/PlaywrightDashboard"])
    #expect(plist["RunAtLoad"] as? Bool == true)
    #expect(plist["KeepAlive"] as? Bool == false)
  }
}
