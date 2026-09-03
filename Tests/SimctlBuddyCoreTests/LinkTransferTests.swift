import Foundation
import XCTest

@testable import SimctlBuddyCore

final class LinkTransferTests: XCTestCase {
  private var directory: URL!
  private var store: LinkStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = LinkStore(fileURL: directory.appendingPathComponent("links.json"))
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func write(_ json: String) throws -> String {
    let url = directory.appendingPathComponent("incoming.json")
    try Data(json.utf8).write(to: url)
    return url.path
  }

  func testExportedFileCanBeImportedBack() throws {
    try store.add(name: "login", url: "myapp://login", force: false)
    try store.add(name: "profile", url: "myapp://profile/42", force: false)

    let exported = try store.export(to: directory.appendingPathComponent("out.json").path)

    let other = LinkStore(fileURL: directory.appendingPathComponent("other.json"))
    let summary = try other.importLinks(fromFileAt: exported)

    XCTAssertEqual(summary.added.sorted(), ["login", "profile"])
    XCTAssertEqual(try other.load(), try store.load())
  }

  func testImportSkipsExistingNamesByDefault() throws {
    try store.add(name: "login", url: "myapp://login", force: false)
    let path = try write(
      """
      [{"name":"login","url":"myapp://changed"},{"name":"cart","url":"myapp://cart"}]
      """)

    let summary = try store.importLinks(fromFileAt: path)

    XCTAssertEqual(summary.added, ["cart"])
    XCTAssertEqual(summary.skipped, ["login"])
    XCTAssertEqual(try store.link(named: "login").url, "myapp://login")
  }

  func testReplaceExistingOverwritesOnlyTheCollisions() throws {
    try store.add(name: "login", url: "myapp://login", force: false)
    try store.add(name: "keep", url: "myapp://keep", force: false)
    let path = try write("""
      [{"name":"login","url":"myapp://changed"}]
      """)

    let summary = try store.importLinks(fromFileAt: path, strategy: .replaceExisting)

    XCTAssertEqual(summary.replaced, ["login"])
    XCTAssertEqual(try store.link(named: "login").url, "myapp://changed")
    XCTAssertEqual(try store.link(named: "keep").url, "myapp://keep")
  }

  func testReplaceAllDropsWhateverWasSaved() throws {
    try store.add(name: "gone", url: "myapp://gone", force: false)
    let path = try write("""
      [{"name":"only","url":"myapp://only"}]
      """)

    let summary = try store.importLinks(fromFileAt: path, strategy: .replaceAll)

    XCTAssertEqual(summary.added, ["only"])
    XCTAssertEqual(try store.load().map(\.name), ["only"])
  }

  func testImportReportsEntriesItCannotUse() throws {
    let path = try write(
      """
      [{"name":"good","url":"myapp://good"},{"name":"bad","url":"no-scheme"},
       {"name":"","url":"myapp://nameless"}]
      """)

    let summary = try store.importLinks(fromFileAt: path)

    XCTAssertEqual(summary.added, ["good"])
    XCTAssertEqual(summary.invalid.count, 2)
    XCTAssertEqual(try store.load().map(\.name), ["good"])
  }

  func testAcceptsAHandWrittenObjectWrapper() throws {
    let path = try write("""
      {"links":[{"name":"cart","url":"myapp://cart"}]}
      """)

    let summary = try store.importLinks(fromFileAt: path)

    XCTAssertEqual(summary.added, ["cart"])
  }

  func testTrimsWhitespaceAroundNamesAndURLs() throws {
    let path = try write("""
      [{"name":"  cart  ","url":"  myapp://cart  "}]
      """)

    try store.importLinks(fromFileAt: path)

    XCTAssertEqual(try store.link(named: "cart").url, "myapp://cart")
  }

  func testAMissingFileIsReportedAsSuch() {
    let missing = directory.appendingPathComponent("nope.json").path
    XCTAssertThrowsError(try store.importLinks(fromFileAt: missing)) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .missingFile(missing))
    }
  }

  func testUnreadableJSONIsReportedWithoutTouchingSavedLinks() throws {
    try store.add(name: "keep", url: "myapp://keep", force: false)
    let path = try write("not json at all")

    XCTAssertThrowsError(try store.importLinks(fromFileAt: path))
    XCTAssertEqual(try store.load().map(\.name), ["keep"])
  }

  func testSummaryDescribesWhatHappened() {
    let summary = ImportSummary(added: ["a"], replaced: ["b"], skipped: ["c"], invalid: ["d"])
    XCTAssertEqual(summary.headline, "1 added, 1 replaced, 1 skipped, 1 invalid")
    XCTAssertEqual(summary.changedCount, 2)
    XCTAssertEqual(summary.details.count, 4)
    XCTAssertEqual(ImportSummary().headline, "That file contained no deep links")
  }
}
