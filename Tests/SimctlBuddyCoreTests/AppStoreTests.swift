import Foundation
import XCTest

@testable import SimctlBuddyCore

final class AppStoreTests: XCTestCase {
  private var directory: URL!
  private var store: AppStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = AppStore(fileURL: directory.appendingPathComponent("apps.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testStartsEmpty() throws {
    XCTAssertEqual(try store.load(), [])
  }

  func testAddsAndFindsAppCaseInsensitively() throws {
    try store.add(name: "Checkout", bundleIdentifier: "com.example.Checkout", force: false)

    XCTAssertEqual(try store.app(named: "checkout").bundleIdentifier, "com.example.Checkout")
  }

  func testRequiresForceToReplaceApp() throws {
    try store.add(name: "Checkout", bundleIdentifier: "com.example.One", force: false)

    XCTAssertThrowsError(
      try store.add(name: "Checkout", bundleIdentifier: "com.example.Two", force: false)
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .duplicateApp("Checkout"))
    }

    try store.add(name: "Checkout", bundleIdentifier: "com.example.Two", force: true)
    XCTAssertEqual(try store.app(named: "Checkout").bundleIdentifier, "com.example.Two")
  }

  func testRemovesApp() throws {
    try store.add(name: "Checkout", bundleIdentifier: "com.example.Checkout", force: false)
    try store.remove(name: "checkout")

    XCTAssertEqual(try store.load(), [])
    XCTAssertThrowsError(try store.remove(name: "Checkout")) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .appNotFound("Checkout"))
    }
  }

  func testRejectsIdentifiersThatAreNotReverseDNS() {
    for invalid in ["", "Checkout", "com..example", "com example", "com.exa mple", "."] {
      XCTAssertThrowsError(
        try store.add(name: "Checkout", bundleIdentifier: invalid, force: true),
        "\(invalid) should be rejected"
      )
    }
  }

  func testAcceptsRealWorldIdentifiers() throws {
    for valid in [
      "com.example.MyApp", "at.spar.mobile.spar-app.ent.qa", "com.example.my_app", "a.b",
    ] {
      try store.add(name: valid, bundleIdentifier: valid, force: true)
    }

    XCTAssertEqual(try store.load().count, 4)
  }

  func testTrimsSurroundingWhitespace() throws {
    try store.add(name: "Checkout", bundleIdentifier: "  com.example.App  ", force: false)

    XCTAssertEqual(try store.app(named: "Checkout").bundleIdentifier, "com.example.App")
  }
}
