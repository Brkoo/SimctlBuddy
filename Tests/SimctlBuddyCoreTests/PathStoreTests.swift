import Foundation
import XCTest

@testable import SimctlBuddyCore

final class PathStoreTests: XCTestCase {
  private var directory: URL!
  private var store: PathStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = PathStore(fileURL: directory.appendingPathComponent("paths.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testStartsEmpty() throws {
    XCTAssertEqual(try store.load(), PathBook())
  }

  func testSavesAndFindsPathCaseInsensitively() throws {
    try store.add(name: "Staging", path: "/builds/MyApp.app", force: false)
    XCTAssertEqual(
      try store.path(named: "staging"),
      SavedPath(name: "Staging", path: "/builds/MyApp.app")
    )
  }

  func testRequiresForceToReplaceAPath() throws {
    try store.add(name: "staging", path: "/builds/One.app", force: false)
    XCTAssertThrowsError(
      try store.add(name: "STAGING", path: "/builds/Two.app", force: false)
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .duplicatePath("STAGING"))
    }

    try store.add(name: "STAGING", path: "/builds/Two.app", force: true)
    XCTAssertEqual(try store.path(named: "staging").path, "/builds/Two.app")
    XCTAssertEqual(try store.saved().count, 1)
  }

  func testRejectsAPathThatIsNotAnAppBundle() {
    XCTAssertThrowsError(try store.add(name: "bad", path: "/builds/MyApp.ipa", force: false)) {
      error in
      XCTAssertEqual(
        error as? SimctlBuddyError, .notAnAppBundlePath("/builds/MyApp.ipa"))
    }
  }

  func testAcceptsAPathThatDoesNotExistYet() throws {
    // A build directory may be empty until the next build runs.
    try store.add(name: "future", path: "/nowhere/NotBuiltYet.app", force: false)
    XCTAssertFalse(try store.path(named: "future").exists)
  }

  func testTrimsATrailingSlashSoTheSamePathIsStoredOnce() throws {
    try store.add(name: "one", path: "/builds/MyApp.app/", force: false)
    XCTAssertEqual(try store.path(named: "one").path, "/builds/MyApp.app")
  }

  func testRemovingAnUnknownPathReports() {
    XCTAssertThrowsError(try store.remove(name: "ghost")) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .pathNotFound("ghost"))
    }
  }

  func testRecentsAreMostRecentFirstWithoutDuplicates() throws {
    try store.recordRecent("/builds/One.app")
    try store.recordRecent("/builds/Two.app")
    try store.recordRecent("/builds/One.app")

    XCTAssertEqual(try store.recents(), ["/builds/One.app", "/builds/Two.app"])
  }

  func testRecentsAreCapped() throws {
    for index in 0...PathStore.recentLimit {
      try store.recordRecent("/builds/App\(index).app")
    }
    let recents = try store.recents()
    XCTAssertEqual(recents.count, PathStore.recentLimit)
    XCTAssertEqual(recents.first, "/builds/App\(PathStore.recentLimit).app")
    XCTAssertFalse(recents.contains("/builds/App0.app"))
  }

  func testClearingRecentsKeepsSavedPaths() throws {
    try store.add(name: "keep", path: "/builds/Keep.app", force: false)
    try store.recordRecent("/builds/One.app")

    try store.clearRecents()

    XCTAssertEqual(try store.recents(), [])
    XCTAssertEqual(try store.saved().count, 1)
  }

  func testSavedPathsComeBackSortedByName() throws {
    try store.add(name: "zebra", path: "/builds/Z.app", force: false)
    try store.add(name: "alpha", path: "/builds/A.app", force: false)
    XCTAssertEqual(try store.saved().map(\.name), ["alpha", "zebra"])
  }
}
