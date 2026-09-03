import XCTest

@testable import SimctlBuddyCore

final class PathCompleterTests: XCTestCase {
  /// A fixed directory tree, so the rules are tested and the file system is not.
  private let tree: [String: [PathEntry]] = [
    "/builds": [
      PathEntry(name: "Checkout.app", isDirectory: true),
      PathEntry(name: "Checkout-Staging.app", isDirectory: true),
      PathEntry(name: "Notes.app", isDirectory: true),
      PathEntry(name: "Debug", isDirectory: true),
      PathEntry(name: "build.log", isDirectory: false),
      PathEntry(name: ".DS_Store", isDirectory: false),
    ],
    "/payloads": [
      PathEntry(name: "welcome.apns", isDirectory: false),
      PathEntry(name: "notes.txt", isDirectory: false),
      PathEntry(name: "archive", isDirectory: true),
    ],
    "/work": [
      PathEntry(name: "MyApp.app", isDirectory: true)
    ],
  ]

  private func completer(currentDirectory: String = "/work") -> PathCompleter {
    let tree = self.tree
    return PathCompleter(
      list: { tree[$0] ?? [] },
      currentDirectory: { currentDirectory }
    )
  }

  func testSplitsDirectoryFromFragment() {
    XCTAssertEqual(PathCompleter.split("/builds/Che").directory, "/builds/")
    XCTAssertEqual(PathCompleter.split("/builds/Che").prefix, "Che")
    XCTAssertEqual(PathCompleter.split("~/builds/").prefix, "")
    XCTAssertEqual(PathCompleter.split("Che").directory, "")
    XCTAssertEqual(PathCompleter.split("Che").prefix, "Che")
  }

  func testUniqueMatchCompletesAndMarksTheBundleAsFinal() {
    let result = completer().complete("/builds/N", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/Notes.app")
    XCTAssertTrue(result.isUnique)
  }

  func testPlainDirectoryGetsATrailingSlashToKeepGoing() {
    let result = completer().complete("/builds/De", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/Debug/")
    XCTAssertTrue(result.isUnique)
  }

  func testAmbiguousMatchFillsInWhatTheNamesShare() {
    let result = completer().complete("/builds/C", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/Checkout")
    XCTAssertFalse(result.isUnique)
    XCTAssertEqual(result.candidates, ["Checkout-Staging.app", "Checkout.app"])
  }

  func testAmbiguousMatchNeverDeletesTypedCharacters() {
    // "Checkout" is already the whole shared prefix, so there is nothing to add.
    let result = completer().complete("/builds/Checkout", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/Checkout")
    XCTAssertEqual(result.candidates.count, 2)
  }

  func testMatchingIsCaseInsensitiveButUsesTheSpellingOnDisk() {
    let result = completer().complete("/builds/notes", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/Notes.app")
  }

  func testNoMatchLeavesTheFieldAlone() {
    let result = completer().complete("/builds/zzz", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/zzz")
    XCTAssertTrue(result.candidates.isEmpty)
    XCTAssertFalse(result.isUnique)
  }

  func testAppBundleFilterHidesFiles() {
    let result = completer().complete("/builds/b", filter: .appBundles)
    XCTAssertEqual(result.value, "/builds/b")
    XCTAssertTrue(result.candidates.isEmpty)
  }

  func testFileFilterKeepsMatchingExtensionsAndDirectories() {
    let payloads = completer().complete("/payloads/", filter: .files(extensions: ["apns", "json"]))
    XCTAssertEqual(payloads.candidates, ["archive/", "welcome.apns"])
  }

  func testDirectoryFilterOffersOnlyDirectories() {
    let result = completer().complete("/payloads/", filter: .directories)
    XCTAssertEqual(result.value, "/payloads/archive/")
    XCTAssertTrue(result.isUnique)
  }

  func testDotfilesStayHiddenUntilAskedForByName() {
    let hidden = completer().complete("/builds/", filter: .any)
    XCTAssertFalse(hidden.candidates.contains(".DS_Store"))

    let asked = completer().complete("/builds/.", filter: .any)
    XCTAssertEqual(asked.value, "/builds/.DS_Store")
  }

  func testBareFragmentCompletesAgainstTheWorkingDirectory() {
    let result = completer().complete("My", filter: .appBundles)
    XCTAssertEqual(result.value, "MyApp.app")
    XCTAssertTrue(result.isUnique)
  }

  func testEmptyDirectoryReturnsTheInputUnchanged() {
    let result = completer().complete("/nowhere/x", filter: .any)
    XCTAssertEqual(result.value, "/nowhere/x")
  }
}
