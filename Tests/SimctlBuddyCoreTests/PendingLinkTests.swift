import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

final class PendingLinkTests: XCTestCase {
  private let devices = [
    SimulatorDevice(
      name: "iPhone 17 Pro", udid: "AAAA", state: "Booted", isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
  ]
  private let at = SavedApp(
    name: "SparAT", bundleIdentifier: "at.spar.mobile.spar-app.ent.qa", scheme: "sparatappqa")
  private let si = SavedApp(
    name: "SparSI", bundleIdentifier: "si.spar.plus.ent.qa", scheme: "sparsiappqa")

  func testAdHocLinksShareOneMemoryEntry() {
    let pending = PendingLink(
      linkName: "", template: LinkTemplate.parse("myapp://x/$id"))
    XCTAssertEqual(pending.memoryKey, LinkValueStore.adHocKey)
    XCTAssertEqual(pending.title, "Open deep link")
  }

  func testASavedLinkIsFiledUnderItsName() {
    let pending = PendingLink(
      linkName: "staging-slot", template: LinkTemplate.parse("$scheme://x?a=$slot"))
    XCTAssertEqual(pending.memoryKey, "staging-slot")
    XCTAssertEqual(pending.title, "staging-slot")
  }

  func testTheDialogNamesTheLinkAndTheParameter() {
    var state = TUIState(devices: devices)
    state.prompt = TUIPrompt(
      kind: .linkParameter(link: "staging-slot", parameter: "slot"),
      label: "Value for $slot",
      value: "staging5"
    )

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 34)

    XCTAssertTrue(screen.contains("staging-slot · $slot"))
    XCTAssertTrue(screen.contains("Value for $slot"))
    XCTAssertTrue(screen.contains("staging5▌"))
  }

  func testAnAdHocParameterDialogStillReads() {
    var state = TUIState(devices: devices)
    state.prompt = TUIPrompt(
      kind: .linkParameter(link: "", parameter: "id"), label: "Value for $id")

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 34)

    XCTAssertTrue(screen.contains("Fill in $id"))
  }

  func testTheDetailsCardExplainsWhatALinkNeeds() {
    var state = TUIState(devices: devices)
    state.apps = [at, si]
    state.links = [
      SavedLink(
        name: "staging-slot",
        url: "$scheme://automation?staging-slot=$slot=staging5",
        apps: ["si.spar.plus.ent.qa"]
      )
    ]
    state.focus = .actions
    state.actionFilter = "staging-slot"

    let screen = TUIRenderer().render(state: state, columns: 132, rows: 40)

    XCTAssertTrue(screen.contains("$scheme"), "the card should mention $scheme")
    XCTAssertTrue(screen.contains("from the app you pick"))
    XCTAssertTrue(screen.contains("$slot"))
    XCTAssertTrue(screen.contains("default staging5"))
    // Restricted links say which app they belong to, by friendly name.
    XCTAssertTrue(screen.contains("SparSI"))
  }

  func testTheCardSaysWhenNoAppCanSupplyTheScheme() {
    var state = TUIState(devices: devices)
    state.apps = [SavedApp(name: "iDart", bundleIdentifier: "com.karlohorvat.iDart")]
    state.links = [SavedLink(name: "bills", url: "$scheme://navigate/bills")]
    state.focus = .actions
    state.actionFilter = "bills"

    let screen = TUIRenderer().render(state: state, columns: 132, rows: 40)

    XCTAssertTrue(screen.contains("no app has one yet"))
  }

  func testAPlainLinkCardStaysAsItWas() {
    var state = TUIState(devices: devices)
    state.links = [SavedLink(name: "bills", url: "sparatappqa://navigate/bills")]
    state.focus = .actions
    state.actionFilter = "bills"

    let screen = TUIRenderer().render(state: state, columns: 132, rows: 40)

    XCTAssertTrue(screen.contains("sparatappqa://navigate/bills"))
    XCTAssertFalse(screen.contains("$scheme"))
    XCTAssertFalse(screen.contains("asked for"))
  }

  func testTheAppPickerShowsEachSchemeItWouldUse() {
    var state = TUIState(devices: devices)
    state.picker = TUIPicker(
      purpose: .linkApp,
      title: "Open on which app?",
      footnote: "Installed apps first · $scheme comes from the app",
      options: [at, si].map {
        TUIPickerOption(
          value: $0.bundleIdentifier, label: $0.name,
          detail: $0.scheme.map { scheme in "\(scheme)://" } ?? "")
      },
      isLoading: false
    )

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 34)

    XCTAssertTrue(screen.contains("Open on which app?"))
    XCTAssertTrue(screen.contains("sparatappqa://"))
    XCTAssertTrue(screen.contains("sparsiappqa://"))
  }

  func testSavedAppsKeepTheirSchemeThroughTheStore() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(fileURL: directory.appendingPathComponent("apps.json"))

    try store.add(
      name: "SparAT", bundleIdentifier: at.bundleIdentifier, scheme: "sparatappqa", force: false)
    try store.add(name: "iDart", bundleIdentifier: "com.karlohorvat.iDart", force: false)

    XCTAssertEqual(try store.app(named: "SparAT").scheme, "sparatappqa")
    XCTAssertNil(try store.app(named: "iDart").scheme)
    XCTAssertEqual(try store.appsWithSchemes().map(\.name), ["SparAT"])
  }

  func testAnInvalidSchemeIsRefused() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AppStore(fileURL: directory.appendingPathComponent("apps.json"))

    XCTAssertThrowsError(
      try store.add(
        name: "Bad", bundleIdentifier: "com.example.App", scheme: "2fast", force: false)
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .invalidScheme("2fast"))
    }
  }

  /// Old apps.json files have no scheme key at all.
  func testAnOlderFileWithoutSchemesStillLoads() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("apps.json")
    try Data(
      """
      [{"name":"SparAT","bundleIdentifier":"at.spar.mobile.spar-app.ent.qa"}]
      """.utf8
    ).write(to: file)

    let apps = try AppStore(fileURL: file).load()

    XCTAssertEqual(apps.count, 1)
    XCTAssertNil(apps[0].scheme)
  }

  /// Old links.json files have no apps key, and plain URLs must keep working.
  func testAnOlderLinksFileStillLoadsAndOpens() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("links.json")
    try Data(
      """
      [{"name":"Purchase popup","url":"sparatappqa://navigate/purchasepopup"}]
      """.utf8
    ).write(to: file)

    let links = try LinkStore(fileURL: file).load()

    XCTAssertEqual(links.count, 1)
    XCTAssertNil(links[0].apps)
    XCTAssertFalse(links[0].template.isTemplate)
    XCTAssertEqual(try links[0].template.render(), "sparatappqa://navigate/purchasepopup")
  }
}
