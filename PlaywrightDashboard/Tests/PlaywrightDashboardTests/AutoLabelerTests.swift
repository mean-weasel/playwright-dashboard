import Testing

@testable import PlaywrightDashboard

@Suite("AutoLabeler.titleCase")
struct AutoLabelerTests {

  @Test("Hyphen-separated words become title case")
  func hyphenSeparated() {
    #expect(AutoLabeler.titleCase(workspaceName: "fix-login-bug") == "Fix Login Bug")
  }

  @Test("Underscore-separated words become title case")
  func underscoreSeparated() {
    #expect(AutoLabeler.titleCase(workspaceName: "add_new_feature") == "Add New Feature")
  }

  @Test("Known abbreviations are uppercased")
  func abbreviations() {
    #expect(AutoLabeler.titleCase(workspaceName: "admin-ux-redesign") == "Admin UX Redesign")
    #expect(AutoLabeler.titleCase(workspaceName: "api-sdk-cli") == "API SDK CLI")
  }

  @Test("Trailing 4-char hex hash is stripped")
  func trailingHash4() {
    #expect(AutoLabeler.titleCase(workspaceName: "admin-ux-25c2") == "Admin UX")
  }

  @Test("Trailing 8-char hex hash is stripped")
  func trailingHash8() {
    #expect(AutoLabeler.titleCase(workspaceName: "feature-a1b2c3d4") == "Feature")
  }

  @Test("9+ char hex-like word is NOT stripped")
  func longHashNotStripped() {
    #expect(AutoLabeler.titleCase(workspaceName: "feature-a1b2c3d4e") == "Feature A1b2c3d4e")
  }

  @Test("Single word that looks like hash is NOT stripped")
  func singleWordHash() {
    #expect(AutoLabeler.titleCase(workspaceName: "a1b2") == "A1b2")
  }

  @Test("Empty input returns empty string")
  func emptyInput() {
    #expect(AutoLabeler.titleCase(workspaceName: "") == "")
  }

  @Test("Mixed hyphens and underscores")
  func mixedSeparators() {
    #expect(AutoLabeler.titleCase(workspaceName: "fix_api-route") == "Fix API Route")
  }
}
