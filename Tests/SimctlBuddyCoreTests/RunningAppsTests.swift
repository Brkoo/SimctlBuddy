import XCTest

@testable import SimctlBuddyCore

final class RunningAppsTests: XCTestCase {
  /// Trimmed from real `simctl spawn <udid> launchctl list` output.
  private let output = """
    PID\tStatus\tLabel
    -\t0\tcom.apple.progressd
    -\t-9\tcom.apple.CoreAuthentication.daemon
    72219\t0\tUIKitApplication:com.apple.mobilecal[1391][rb-legacy]
    13566\t0\tUIKitApplication:com.karlohorvat.iDart[b724][rb-legacy]
    71981\t0\tUIKitApplication:com.apple.chrono.WidgetRenderer-Default[47db][rb-legacy]
    501\t0\tcom.apple.backboardd
    """

  func testReadsBundleIdentifiersOfRunningApps() {
    XCTAssertEqual(
      SimctlClient.parseRunningBundleIdentifiers(output),
      [
        "com.apple.chrono.WidgetRenderer-Default",
        "com.apple.mobilecal",
        "com.karlohorvat.iDart",
      ]
    )
  }

  func testJobsWithoutAProcessAreNotRunning() {
    let registered = """
      PID\tStatus\tLabel
      -\t0\tUIKitApplication:com.example.NotRunning[aaaa][rb-legacy]
      """
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers(registered), [])
  }

  func testNonAppJobsAreIgnored() {
    let daemons = """
      PID\tStatus\tLabel
      501\t0\tcom.apple.backboardd
      502\t0\tcom.apple.springboard
      """
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers(daemons), [])
  }

  func testTheSameAppListedTwiceIsReportedOnce() {
    let duplicated = """
      PID\tStatus\tLabel
      100\t0\tUIKitApplication:com.example.App[aaaa][rb-legacy]
      101\t0\tUIKitApplication:com.example.App[bbbb][rb-legacy]
      """
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers(duplicated), ["com.example.App"])
  }

  func testEmptyOutputIsNotAnError() {
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers(""), [])
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers("PID\tStatus\tLabel"), [])
  }

  func testSomethingThatIsNotABundleIdentifierIsSkipped() {
    let odd = """
      PID\tStatus\tLabel
      100\t0\tUIKitApplication:notreversedns[aaaa][rb-legacy]
      """
    XCTAssertEqual(SimctlClient.parseRunningBundleIdentifiers(odd), [])
  }
}
