import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

final class TUIStateTests: XCTestCase {
  private let devices = [
    SimulatorDevice(
      name: "iPhone 17 Pro",
      udid: "AAAA-BBBB",
      state: "Booted",
      isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    ),
    SimulatorDevice(
      name: "iPhone 17",
      udid: "CCCC-DDDD",
      state: "Shutdown",
      isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    ),
  ]

  func testDeviceSelectionWrapsInBothDirections() {
    var state = TUIState(devices: devices)

    state.moveSelection(by: -1)
    XCTAssertEqual(state.selectedDevice?.udid, "CCCC-DDDD")

    state.moveSelection(by: 1)
    XCTAssertEqual(state.selectedDevice?.udid, "AAAA-BBBB")
  }

  func testActionSelectionWraps() {
    var state = TUIState(devices: devices)
    state.focus = .actions

    state.moveSelection(by: -1)

    XCTAssertEqual(state.actions[state.selectedActionIndex].id, .refresh)
  }

  func testSavedLinksBecomeActions() {
    let link = SavedLink(name: "Login", url: "myapp://login")
    let state = TUIState(devices: devices, links: [link])

    XCTAssertTrue(
      state.actions.contains(TUIActionItem(id: .savedLink(link), title: "↗ Login", hint: "↵/e")))
  }

  func testAddSavedLinkIsAvailableAsAnAction() {
    let state = TUIState(devices: devices)

    XCTAssertTrue(
      state.actions.contains(
        TUIActionItem(id: .addSavedLink, title: "Add saved deep link", hint: "a")))
  }

  func testRendererShowsPanelsAndSelectedDevice() {
    var state = TUIState(devices: devices)
    state.output = ["✓ Ready"]

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 30)

    XCTAssertTrue(screen.contains("Devices 2"))
    XCTAssertTrue(screen.contains("Actions"))
    XCTAssertTrue(screen.contains("Details / Output"))
    XCTAssertTrue(screen.contains("iPhone 17 Pro"))
    XCTAssertTrue(screen.contains("✓ Ready"))
  }

  func testRendererExplainsMinimumTerminalSize() {
    let screen = TUIRenderer().render(state: TUIState(), columns: 60, rows: 15)

    XCTAssertTrue(screen.contains("needs at least 78×18 columns"))
  }

  func testRendererShowsPromptInCenteredDialog() {
    var state = TUIState(devices: devices)
    state.prompt = TUIPrompt(kind: .deepLink, label: "URL")

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 30)

    XCTAssertTrue(screen.contains("\u{001B}[11;25H"))
    XCTAssertTrue(screen.contains("Open deep link"))
    XCTAssertTrue(screen.contains("Example: myapp://profile/42"))
  }

  func testRendererShowsSavedLinkURLInDetails() {
    let link = SavedLink(name: "Login", url: "myapp://login")
    var state = TUIState(devices: devices, links: [link])
    state.selectedActionIndex = 2

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 30)

    XCTAssertTrue(screen.contains("myapp://login"))
    XCTAssertTrue(screen.contains("Press e to edit its URL."))
  }

  func testRendererShowsPrefilledEditDialog() {
    var state = TUIState(devices: devices)
    state.prompt = TUIPrompt(
      kind: .editSavedLinkURL(name: "Login"),
      label: "URL",
      value: "myapp://login"
    )

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 30)

    XCTAssertTrue(screen.contains("Edit saved deep link"))
    XCTAssertTrue(screen.contains("› myapp://login▌"))
    XCTAssertTrue(screen.contains("Ctrl+U clear"))
  }
}
