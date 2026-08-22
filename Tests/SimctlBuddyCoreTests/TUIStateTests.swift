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
      state.actions.contains(TUIActionItem(id: .savedLink(link), title: "↗ Login", hint: "saved")))
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
}
