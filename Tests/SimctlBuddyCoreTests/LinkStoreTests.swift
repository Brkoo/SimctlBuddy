import Foundation
import XCTest

@testable import SimctlBuddyCore

final class LinkStoreTests: XCTestCase {
  private var directory: URL!
  private var store: LinkStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = LinkStore(fileURL: directory.appendingPathComponent("links.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testStartsEmpty() throws {
    XCTAssertEqual(try store.load(), [])
  }

  func testAddsAndFindsLinkCaseInsensitively() throws {
    try store.add(name: "Login", url: "myapp://login", force: false)
    XCTAssertEqual(
      try store.link(named: "login"),
      SavedLink(name: "Login", url: "myapp://login")
    )
  }

  func testRequiresForceToReplaceLink() throws {
    try store.add(name: "login", url: "myapp://login", force: false)
    XCTAssertThrowsError(
      try store.add(name: "LOGIN", url: "myapp://new-login", force: false)
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .duplicateLink("LOGIN"))
    }

    try store.add(name: "LOGIN", url: "myapp://new-login", force: true)
    XCTAssertEqual(try store.link(named: "login").url, "myapp://new-login")
  }

  func testRemovesLink() throws {
    try store.add(name: "profile", url: "myapp://profile", force: false)
    try store.remove(name: "profile")
    XCTAssertEqual(try store.load(), [])
  }
}
