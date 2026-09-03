import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

final class PromptCompletionTests: XCTestCase {
  private let completer = PathCompleter(
    list: { path in
      guard path == "/builds" else { return [] }
      return [
        PathEntry(name: "Checkout.app", isDirectory: true),
        PathEntry(name: "Checkout-Staging.app", isDirectory: true),
        PathEntry(name: "Notes.app", isDirectory: true),
      ]
    },
    currentDirectory: { "/work" }
  )

  func testOnlyPathFieldsOfferCompletion() {
    XCTAssertTrue(TUIPrompt(kind: .installApp, label: "Path").supportsCompletion)
    XCTAssertTrue(TUIPrompt(kind: .screenshotDirectory, label: "Folder").supportsCompletion)
    XCTAssertTrue(TUIPrompt(kind: .importLinks, label: "File").supportsCompletion)
    XCTAssertFalse(TUIPrompt(kind: .deepLink, label: "URL").supportsCompletion)
    XCTAssertFalse(TUIPrompt(kind: .launchApp, label: "Bundle").supportsCompletion)
  }

  func testEachPathFieldAsksForTheRightKindOfEntry() {
    XCTAssertEqual(TUIPromptKind.installApp.pathFilter, .appBundles)
    XCTAssertEqual(TUIPromptKind.screenshotDirectory.pathFilter, .directories)
    XCTAssertEqual(TUIPromptKind.recordingDirectory.pathFilter, .directories)
    XCTAssertEqual(
      TUIPromptKind.pushPayload(bundleIdentifier: "com.example.App").pathFilter,
      .files(extensions: ["apns", "json"]))
    XCTAssertEqual(TUIPromptKind.exportLinks.pathFilter, .files(extensions: ["json"]))
    XCTAssertNil(TUIPromptKind.clipboard.pathFilter)
  }

  func testUniqueCompletionFillsTheFieldAndSaysNothingMore() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path", value: "/builds/N")

    XCTAssertTrue(prompt.complete(using: completer))

    XCTAssertEqual(prompt.value, "/builds/Notes.app")
    XCTAssertTrue(prompt.candidates.isEmpty)
    XCTAssertNil(prompt.note)
  }

  func testAmbiguousCompletionListsTheMatches() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path", value: "/builds/C")

    XCTAssertTrue(prompt.complete(using: completer))

    XCTAssertEqual(prompt.value, "/builds/Checkout")
    XCTAssertEqual(prompt.candidates, ["Checkout-Staging.app", "Checkout.app"])
    XCTAssertEqual(prompt.note, "2 matches")
  }

  func testNoMatchSaysSoWithoutChangingTheField() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path", value: "/builds/zz")

    XCTAssertFalse(prompt.complete(using: completer))

    XCTAssertEqual(prompt.value, "/builds/zz")
    XCTAssertEqual(prompt.note, "No match")
    XCTAssertTrue(prompt.candidates.isEmpty)
  }

  func testCompletingAFieldThatDoesNotHoldAPathDoesNothing() {
    var prompt = TUIPrompt(kind: .deepLink, label: "URL", value: "myapp://")

    XCTAssertFalse(prompt.complete(using: completer))

    XCTAssertEqual(prompt.value, "myapp://")
    XCTAssertNil(prompt.note)
  }

  func testClearingCompletionRemovesTheStaleList() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path", value: "/builds/C")
    prompt.complete(using: completer)

    prompt.clearCompletion()

    XCTAssertTrue(prompt.candidates.isEmpty)
    XCTAssertNil(prompt.note)
  }

  func testTheDialogShowsAmbiguousMatchesUnderTheField() {
    var state = TUIState(devices: [])
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "/builds/C")
    prompt.complete(using: completer)
    state.prompt = prompt

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertTrue(screen.contains("2 matches"))
    XCTAssertTrue(screen.contains("Checkout.app"))
    XCTAssertTrue(screen.contains("Tab"))
  }

  func testTheDialogOffersNoTabHintWhereItWouldDoNothing() {
    var state = TUIState(devices: [])
    state.prompt = TUIPrompt(kind: .clipboard, label: "Text to copy", value: "hello")

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertFalse(screen.contains("complete"))
  }
}
