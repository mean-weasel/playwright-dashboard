import Testing

@testable import PlaywrightDashboard

@Suite("PlaywrightCLIStatusProvider")
struct PlaywrightCLIStatusProviderTests {

  @Test("reports available with version output")
  func availableWithVersion() async {
    let provider = PlaywrightCLIStatusProvider { args in
      #expect(args == ["--version"])
      return ProcessResult(exitStatus: 0, output: "1.2.3\n")
    }

    #expect(await provider.status() == .available("1.2.3"))
  }

  @Test("reports available without a version when output is empty")
  func availableWithoutVersion() async {
    let provider = PlaywrightCLIStatusProvider { _ in
      ProcessResult(exitStatus: 0, output: "")
    }

    #expect(await provider.status() == .available(nil))
  }

  @Test("reports unavailable on command failure")
  func unavailableOnFailure() async {
    let provider = PlaywrightCLIStatusProvider { _ in
      ProcessResult(exitStatus: 127, output: "not found")
    }

    #expect(await provider.status() == .unavailable)
  }

  @Test("reports unavailable when runner throws")
  func unavailableOnThrow() async {
    let provider = PlaywrightCLIStatusProvider { _ in
      throw SessionTerminationError.executableNotFound
    }

    #expect(await provider.status() == .unavailable)
  }
}
