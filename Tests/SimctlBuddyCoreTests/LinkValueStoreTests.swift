import Foundation
import XCTest

@testable import SimctlBuddyCore

final class LinkValueStoreTests: XCTestCase {
  private var directory: URL!
  private var store: LinkValueStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = LinkValueStore(fileURL: directory.appendingPathComponent("link-values.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testStartsFromTheTemplateDefault() {
    let parameter = LinkParameter(name: "slot", defaultValue: "staging5")
    XCTAssertEqual(store.startingValue(for: parameter, link: "staging"), "staging5")
  }

  func testThenStartsFromWhatWasUsedLast() throws {
    let parameter = LinkParameter(name: "slot", defaultValue: "staging5")
    try store.remember(values: ["slot": "staging7"], app: nil, for: "staging")
    XCTAssertEqual(store.startingValue(for: parameter, link: "staging"), "staging7")
  }

  func testWithNoDefaultAndNoHistoryTheFieldStartsEmpty() {
    XCTAssertEqual(store.startingValue(for: LinkParameter(name: "id"), link: "profile"), "")
  }

  func testValuesAreRememberedPerLink() throws {
    try store.remember(values: ["slot": "a"], app: nil, for: "one")
    try store.remember(values: ["slot": "b"], app: nil, for: "two")

    XCTAssertEqual(store.memory(for: "one").values["slot"], "a")
    XCTAssertEqual(store.memory(for: "two").values["slot"], "b")
  }

  func testTheAppIsRememberedToo() throws {
    try store.remember(values: [:], app: "si.spar.plus.ent.qa", for: "bills")
    XCTAssertEqual(store.memory(for: "bills").app, "si.spar.plus.ent.qa")
  }

  func testRememberingMergesRatherThanReplacing() throws {
    try store.remember(values: ["a": "1"], app: "app.one", for: "link")
    try store.remember(values: ["b": "2"], app: nil, for: "link")

    let memory = store.memory(for: "link")
    XCTAssertEqual(memory.values, ["a": "1", "b": "2"])
    // A run that did not choose an app must not erase the remembered one.
    XCTAssertEqual(memory.app, "app.one")
  }

  func testForgettingOneLinkLeavesTheOthers() throws {
    try store.remember(values: ["slot": "a"], app: nil, for: "one")
    try store.remember(values: ["slot": "b"], app: nil, for: "two")

    try store.forget("one")

    XCTAssertTrue(store.memory(for: "one").values.isEmpty)
    XCTAssertEqual(store.memory(for: "two").values["slot"], "b")
  }

  func testAMissingFileIsNotAnError() throws {
    XCTAssertEqual(try store.load(), [:])
    XCTAssertTrue(store.memory(for: "anything").values.isEmpty)
  }
}
