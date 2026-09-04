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
      state.actions.contains(TUIActionItem(id: .savedLink(link), title: "↗ Login", hint: "↵/e/d")))
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
    XCTAssertTrue(screen.contains("Details"))
    XCTAssertTrue(screen.contains("Activity"))
    XCTAssertTrue(screen.contains("iPhone 17 Pro"))
    XCTAssertTrue(screen.contains("✓ Ready"))
  }

  func testRendererExplainsMinimumTerminalSize() {
    let screen = TUIRenderer().render(state: TUIState(), columns: 60, rows: 15)

    XCTAssertTrue(screen.contains("needs a terminal of at least 78×18"))
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
    // Found rather than hardcoded, so reordering the action list does not break
    // a test about what the details pane says.
    state.selectedActionIndex = try! XCTUnwrap(
      state.actions.firstIndex { $0.id == .savedLink(link) })

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
    XCTAssertTrue(screen.contains("myapp://login▌"))
    XCTAssertTrue(screen.contains("Ctrl+U clear"))
  }

  func testRendererGroupsActionsIntoSections() {
    var state = TUIState(devices: devices)
    state.paths = [SavedPath(name: "Staging", path: "/builds/Staging.app")]

    // Tall enough for every section: the menu no longer fits in 40 rows.
    let screen = TUIRenderer().render(state: state, columns: 132, rows: 60)

    for section in [
      "LINKS", "SAVED BUILDS", "DEVICE", "APPS", "PRIVACY", "CAPTURE", "APPEARANCE", "SYSTEM",
    ] {
      XCTAssertTrue(screen.contains(section), "missing section \(section)")
    }
  }

  func testRendererFillsTheAvailableHeight() {
    var state = TUIState(devices: devices)
    state.output = ["✓ Ready"]

    for rows in [24, 44, 90] {
      let screen = TUIRenderer().render(state: state, columns: 132, rows: rows)

      XCTAssertEqual(screen.components(separatedBy: "\r\n").count, rows)
    }
  }

  func testRendererWrapsLongActivityEntriesInsteadOfClipping() {
    var state = TUIState(devices: devices)
    state.output = [
      "✓ Opened the saved deep link on the selected simulator without losing the tail"
    ]

    let screen = TUIRenderer().render(state: state, columns: 100, rows: 40)

    XCTAssertTrue(screen.contains("✓ Opened the saved deep link"))
    XCTAssertTrue(screen.contains("tail"))
  }

  func testRendererShowsEmptyStateHints() {
    let screen = TUIRenderer().render(state: TUIState(), columns: 100, rows: 30)

    XCTAssertTrue(screen.contains("No devices found"))
    XCTAssertTrue(screen.contains("No device selected"))
  }

  func testScreenModeGrowsAndShrinksWithinBounds() {
    var state = TUIState(devices: devices)

    XCTAssertEqual(state.screenMode, .normal)
    state.growFocusedPanel()
    XCTAssertEqual(state.screenMode, .half)
    state.growFocusedPanel()
    XCTAssertEqual(state.screenMode, .full)
    state.growFocusedPanel()
    XCTAssertEqual(state.screenMode, .full, "grow must clamp at the largest mode")
    state.shrinkFocusedPanel()
    XCTAssertEqual(state.screenMode, .half)
    state.shrinkFocusedPanel()
    state.shrinkFocusedPanel()
    XCTAssertEqual(state.screenMode, .normal, "shrink must clamp at the smallest mode")
  }

  func testHalfModeWidensTheFocusedPanel() {
    let udid = "B2BDA61B-C0AC-46F9-B655-9DA559AA7FD4"
    let device = SimulatorDevice(
      name: "iPhone 17 Pro", udid: udid, state: "Booted", isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
    var state = TUIState(devices: [device])
    state.focus = .devices

    let normal = TUIRenderer().render(state: state, columns: 120, rows: 26)
    state.screenMode = .half
    let half = TUIRenderer().render(state: state, columns: 120, rows: 26)

    XCTAssertFalse(normal.contains(udid), "the narrow details card should clip the UDID")
    XCTAssertTrue(half.contains(udid), "the widened details card should show the whole UDID")
  }

  func testFullModeShowsOnlyTheFocusedPanel() {
    var state = TUIState(devices: devices)
    state.screenMode = .full

    state.focus = .devices
    let devicesFull = TUIRenderer().render(state: state, columns: 120, rows: 26)
    XCTAssertTrue(devicesFull.contains("Devices 2"))
    XCTAssertTrue(devicesFull.contains("Details"))
    XCTAssertFalse(devicesFull.contains("Activity"))

    state.focus = .actions
    let actionsFull = TUIRenderer().render(state: state, columns: 120, rows: 26)
    XCTAssertTrue(actionsFull.contains("Actions"))
    XCTAssertFalse(actionsFull.contains("Devices 2"))
  }

  func testEveryModeStaysWithinTheTerminalWidth() {
    var state = TUIState(devices: devices, links: [SavedLink(name: "Login", url: "myapp://login")])
    state.output = ["✓ Opened myapp://login"]

    for mode in [TUIScreenMode.normal, .half, .full] {
      for focus in [TUIFocus.devices, TUIFocus.actions] {
        for (columns, rows) in [(78, 18), (120, 26), (200, 60)] {
          state.screenMode = mode
          state.focus = focus
          let screen = TUIRenderer().render(state: state, columns: columns, rows: rows)

          for line in screen.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(
              Self.stripANSI(line).count, columns,
              "\(mode)/\(focus) at \(columns)×\(rows) overflowed")
          }
        }
      }
    }
  }

  private static func stripANSI(_ value: String) -> String {
    var result = ""
    var inEscape = false
    for character in value {
      if character == "\u{001B}" {
        inEscape = true
        continue
      }
      if inEscape {
        if character.isLetter { inEscape = false }
        continue
      }
      result.append(character)
    }
    return result
  }

  private var filterDevices: [SimulatorDevice] {
    [
      ("iPhone 17 Pro", "iOS-26-5"), ("iPhone 12 mini", "iOS-18-6"),
      ("iPad Pro 11-inch", "iOS-26-5"), ("iPhone SE (3rd generation)", "iOS-18-6"),
    ].enumerated().map { index, pair in
      SimulatorDevice(
        name: pair.0, udid: "udid-\(index)", state: "Shutdown", isAvailable: true,
        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.\(pair.1)")
    }
  }

  func testDeviceFilterMatchesNameAndRuntime() {
    var state = TUIState(devices: filterDevices)

    state.deviceFilter = "pro"
    XCTAssertEqual(state.visibleDevices.map(\.name), ["iPhone 17 Pro", "iPad Pro 11-inch"])

    state.deviceFilter = "18.6"
    XCTAssertEqual(
      state.visibleDevices.map(\.name), ["iPhone 12 mini", "iPhone SE (3rd generation)"])

    state.deviceFilter = "nothing here"
    XCTAssertTrue(state.visibleDevices.isEmpty)
  }

  func testFilteredSelectionTargetsTheVisibleDevice() {
    var state = TUIState(devices: filterDevices)
    state.deviceFilter = "mini"
    state.clampSelections()

    XCTAssertEqual(state.selectedDevice?.name, "iPhone 12 mini")

    // Selection must not point past the end when the filter narrows further.
    state.selectedDeviceIndex = 3
    state.clampSelections()
    XCTAssertEqual(state.selectedDevice?.name, "iPhone 12 mini")
  }

  func testActionFilterMatchesSavedLinkURL() {
    let links = [
      SavedLink(name: "Purchase popup", url: "myapp://navigate/purchasepopup"),
      SavedLink(name: "Bills", url: "myapp://navigate/bills"),
    ]
    var state = TUIState(devices: devices, links: links)
    state.focus = .actions

    state.actionFilter = "bills"
    XCTAssertEqual(state.visibleActions.count, 1)
    XCTAssertEqual(state.selectedAction?.title, "↗ Bills")

    state.actionFilter = "screenshot"
    XCTAssertEqual(
      state.visibleActions.map(\.title), ["Take screenshot", "Set screenshot folder"])
  }

  func testClearingTheActiveFilterRestoresTheFullList() {
    var state = TUIState(devices: filterDevices)
    state.focus = .devices
    state.activeFilter = "mini"
    XCTAssertEqual(state.visibleDevices.count, 1)

    state.clearActiveFilter()

    XCTAssertEqual(state.visibleDevices.count, filterDevices.count)
    XCTAssertEqual(state.selectedDeviceIndex, 0)
  }

  func testActiveFilterFollowsFocus() {
    var state = TUIState(devices: filterDevices)
    state.focus = .devices
    state.activeFilter = "pro"
    state.focus = .actions
    state.activeFilter = "boot"

    XCTAssertEqual(state.deviceFilter, "pro", "each panel keeps its own filter")
    XCTAssertEqual(state.actionFilter, "boot")
  }

  func testMovingSelectionWrapsWithinTheFilteredList() {
    var state = TUIState(devices: filterDevices)
    state.deviceFilter = "pro"

    state.moveSelection(by: 1)
    XCTAssertEqual(state.selectedDevice?.name, "iPad Pro 11-inch")
    state.moveSelection(by: 1)
    XCTAssertEqual(state.selectedDevice?.name, "iPhone 17 Pro", "must wrap at the filtered end")
  }

  func testRendererShowsFilterCountsAndSpinner() {
    var state = TUIState(devices: filterDevices)
    state.deviceFilter = "pro"
    state.busy = "Booting iPhone 17 Pro"
    state.spinnerFrame = 3

    let screen = TUIRenderer().render(state: state, columns: 132, rows: 30)

    XCTAssertTrue(screen.contains("Devices 2/4 · /pro"))
    XCTAssertTrue(screen.contains("Booting iPhone 17 Pro…"))
  }

  func testRendererShowsNoMatchHint() {
    var state = TUIState(devices: filterDevices)
    state.deviceFilter = "zzz"

    let screen = TUIRenderer().render(state: state, columns: 132, rows: 30)

    XCTAssertTrue(screen.contains("No devices match /zzz"))
  }
}

private struct RecordingRunner: CommandRunning {
  let outputs: [String: CommandResult]

  func run(executable: String, arguments: [String], standardInput: Data?) throws -> CommandResult {
    let key = arguments.first ?? ""
    return outputs[key]
      ?? CommandResult(standardOutput: "", standardError: "unexpected", exitCode: 1)
  }
}

final class TUIActionCoverageTests: XCTestCase {
  private var state: TUIState {
    TUIState(
      devices: [
        SimulatorDevice(
          name: "iPhone 17 Pro", udid: "udid", state: "Booted", isAvailable: true,
          runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
      ],
      links: [SavedLink(name: "Login", url: "myapp://login")])
  }

  func testEveryCLIFeatureIsReachableFromTheActionsPanel() {
    let ids = state.actions.map(\.id)

    for expected: TUIActionID in [
      .push, .privacy(.grant), .privacy(.revoke), .privacyReset,
      .listApps, .clipboardPaste, .locationClear, .doctor,
    ] {
      XCTAssertTrue(ids.contains(expected), "\(expected) has no action entry")
    }
  }

  func testSavedLinkHintAdvertisesDeletion() {
    let savedLink = state.actions.first { if case .savedLink = $0.id { return true } else { return false } }

    XCTAssertEqual(savedLink?.hint, "↵/e/d")
  }

  func testOnlyRemovalPromptsAskForConfirmation() {
    XCTAssertTrue(TUIPromptKind.confirmRemoveSavedLink(name: "Login").isConfirmation)
    XCTAssertFalse(TUIPromptKind.pushBundle.isConfirmation)
    XCTAssertFalse(TUIPromptKind.deepLink.isConfirmation)
  }

  func testConfirmationDialogHidesTheTextField() {
    var confirming = state
    confirming.prompt = TUIPrompt(
      kind: .confirmRemoveSavedLink(name: "Login"), label: "Delete “Login” → myapp://login?")

    let screen = TUIRenderer().render(state: confirming, columns: 120, rows: 30)

    XCTAssertTrue(screen.contains("Delete saved deep link"))
    XCTAssertTrue(screen.contains("This cannot be undone."))
    XCTAssertTrue(screen.contains("keep it"))
    XCTAssertFalse(screen.contains("Ctrl+U clear"), "confirmations take no typed input")
  }

  func testReportDetailLinesKeepTheirIndentWhenWrapped() {
    var reporting = state
    reporting.output = [
      "✓ Diagnostics passed",
      "  Developer directory: /Applications/Some-Very-Long-Xcode-Path.app/Contents/Developer",
    ]

    let screen = TUIRenderer().render(state: reporting, columns: 120, rows: 30)

    // The headline stays flush; the detail keeps its two-space indent even after
    // wrapping, which a previous version dropped.
    XCTAssertTrue(screen.contains("  Developer directory:"))
    XCTAssertFalse(screen.contains("│Developer directory:"))
  }

  func testInstalledBundleIdentifiersAreParsedAndSorted() throws {
    let listing = """
      com.example.Zebra = {
          CFBundleIdentifier = "com.example.Zebra";
      };
      com.example.Alpha = {
          CFBundleIdentifier = "com.example.Alpha";
      };
      """
    let client = SimctlClient(
      runner: RecordingRunner(outputs: [
        "simctl": CommandResult(standardOutput: listing, standardError: "", exitCode: 0)
      ]))
    let device = SimulatorDevice(
      name: "iPhone", udid: "udid", state: "Booted", isAvailable: true)

    let identifiers = try client.installedBundleIdentifiers(device: device)

    XCTAssertEqual(identifiers, ["com.example.Alpha", "com.example.Zebra"])
  }

  func testDiagnosticsReportsSetupProblemWhenXcodeIsNotSelected() {
    let client = SimctlClient(
      runner: RecordingRunner(outputs: [
        "-p": CommandResult(standardOutput: "", standardError: "error", exitCode: 1)
      ]))

    XCTAssertThrowsError(try client.diagnostics()) { error in
      XCTAssertEqual(
        error as? SimctlBuddyError,
        .setupProblem(
          "Xcode command-line tools are not selected. Run `sudo xcode-select -s /Applications/Xcode.app`."
        ))
    }
  }
}

final class TUIPickerTests: XCTestCase {
  private let options = [
    TUIPickerOption(value: "com.example.Saved", label: "Checkout", detail: "com.example.Saved"),
    TUIPickerOption(value: "com.apple.MobileSMS", label: "com.apple.MobileSMS", detail: "installed"),
    TUIPickerOption(value: "com.apple.mobilecal", label: "com.apple.mobilecal", detail: "installed"),
  ]

  func testPickerFiltersOnLabelAndValue() {
    var picker = TUIPicker(purpose: .launchApp, title: "Launch app", options: options)

    picker.query = "checkout"
    XCTAssertEqual(picker.visibleOptions.map(\.value), ["com.example.Saved"])

    // Saved apps must stay findable by their identifier, not only their name.
    picker.query = "com.example"
    XCTAssertEqual(picker.visibleOptions.map(\.value), ["com.example.Saved"])

    picker.query = "mobile"
    XCTAssertEqual(picker.visibleOptions.count, 2)
  }

  func testPickerSelectionWrapsWithinFilteredOptions() {
    var picker = TUIPicker(purpose: .launchApp, title: "Launch app", options: options)
    picker.query = "mobile"

    picker.moveSelection(by: 1)
    XCTAssertEqual(picker.selectedOption?.value, "com.apple.mobilecal")
    picker.moveSelection(by: 1)
    XCTAssertEqual(picker.selectedOption?.value, "com.apple.MobileSMS")
  }

  func testPickerHasNoSelectionWhenNothingMatches() {
    var picker = TUIPicker(purpose: .launchApp, title: "Launch app", options: options)
    picker.query = "nothing"

    XCTAssertNil(picker.selectedOption)
  }

  func testRendererShowsPickerOptionsOverTheDeck() {
    var state = TUIState(devices: [
      SimulatorDevice(
        name: "iPhone 17 Pro", udid: "udid", state: "Booted", isAvailable: true,
        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
    ])
    state.picker = TUIPicker(
      purpose: .launchApp, title: "Launch app", options: options, isLoading: false)

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertTrue(screen.contains("Launch app"))
    XCTAssertTrue(screen.contains("Checkout"))
    XCTAssertTrue(screen.contains("com.apple.MobileSMS"))
    XCTAssertTrue(screen.contains("Tab"))
  }

  func testRendererShowsLoadingStateBeforeAppsArrive() {
    var state = TUIState(devices: [])
    state.picker = TUIPicker(purpose: .launchApp, title: "Launch app")

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertTrue(screen.contains("Reading installed apps…"))
  }

  func testSavedAppsBecomeActionsAndMatchTheirIdentifier() {
    var state = TUIState(devices: [])
    state.apps = [SavedApp(name: "Checkout", bundleIdentifier: "com.example.Checkout")]
    state.focus = .actions

    XCTAssertTrue(
      state.actions.contains(
        TUIActionItem(
          id: .savedApp(SavedApp(name: "Checkout", bundleIdentifier: "com.example.Checkout")),
          title: "▶ Checkout", hint: "↵/e/d")))

    state.actionFilter = "com.example"
    XCTAssertEqual(state.visibleActions.map(\.title), ["▶ Checkout"])
  }

  func testRemovalConfirmationCoversSavedApps() {
    XCTAssertTrue(TUIPromptKind.confirmRemoveSavedApp(name: "Checkout").isConfirmation)
    XCTAssertFalse(TUIPromptKind.savedAppName(bundleIdentifier: "com.example.App").isConfirmation)
  }

  func testSavedBuildsBecomeActionsAndMatchTheirPath() {
    var state = TUIState(devices: [])
    state.paths = [SavedPath(name: "Staging", path: "/builds/Staging.app")]
    state.focus = .actions

    XCTAssertTrue(state.actions.contains { $0.title == "⤓ Staging" })

    state.actionFilter = "/builds"
    XCTAssertEqual(state.visibleActions.map(\.title), ["⤓ Staging"])
  }

  func testRecordingActionFlipsBetweenStartAndStop() {
    var state = TUIState(devices: [])
    XCTAssertFalse(state.isRecording)
    XCTAssertTrue(state.actions.contains { $0.id == .startRecording })
    XCTAssertFalse(state.actions.contains { $0.id == .stopRecording })

    state.recording = Recorder.Session(
      deviceUDID: "AAAA-BBBB",
      deviceName: "iPhone 17 Pro",
      path: "/movies/clip.mov",
      startedAt: Date()
    )

    XCTAssertTrue(state.isRecording)
    XCTAssertTrue(state.actions.contains { $0.id == .stopRecording })
    XCTAssertFalse(state.actions.contains { $0.id == .startRecording })
  }

  func testHeaderShowsThatARecordingIsRunning() {
    var state = TUIState(devices: [])
    state.recording = Recorder.Session(
      deviceUDID: "AAAA-BBBB",
      deviceName: "iPhone 17 Pro",
      path: "/movies/clip.mov",
      startedAt: Date(timeIntervalSinceNow: -75)
    )

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertTrue(screen.contains("REC"))
    XCTAssertTrue(screen.contains("1:15"))
  }

  func testRemovalConfirmationCoversSavedBuilds() {
    XCTAssertTrue(TUIPromptKind.confirmRemoveSavedPath(name: "Staging").isConfirmation)
    XCTAssertFalse(TUIPromptKind.savedPathName(path: "/builds/A.app").isConfirmation)
  }

  func testPickerDescribesWhatItIsLoading() {
    var state = TUIState(devices: [])
    state.picker = TUIPicker(
      purpose: .terminateApp,
      title: "Terminate app",
      footnote: "Running apps first, then everything installed",
      loadingMessage: "Reading running apps"
    )

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 32)

    XCTAssertTrue(screen.contains("Reading running apps…"))
    XCTAssertTrue(screen.contains("Running apps first"))
  }
}

final class ConfigurablePanelWidthTests: XCTestCase {
  private func state(device: Double?, action: Double?) -> TUIState {
    var state = TUIState(devices: [
      Device(
        name: "iPhone 16 Pro Max Simulator", udid: "S1", state: "Booted", isAvailable: true)
    ])
    state.settings = Settings(devicePanelWidth: device, actionPanelWidth: action)
    return state
  }

  /// Width is measured from the frame the renderer draws, not from the setting,
  /// so this fails if the value is stored but never used.
  private func devicePanelWidth(_ state: TUIState, columns: Int = 160) -> Int {
    let screen = TUIRenderer().render(state: state, columns: columns, rows: 30)
    let plain = screen.replacingOccurrences(
      of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    // The devices panel is the first box on the row, so its width is the offset
    // of the second box's left edge.
    guard
      let line = plain.components(separatedBy: "\r\n").first(where: {
        $0.filter { $0 == "┌" || $0 == "+" }.count >= 2
      })
    else { return 0 }
    let opens = line.enumerated().filter { $0.element == "┌" || $0.element == "+" }
    guard opens.count >= 2 else { return 0 }
    return opens[1].offset - opens[0].offset
  }

  func testAWiderShareDrawsAWiderPanel() {
    let narrow = devicePanelWidth(state(device: 0.2, action: 0.3))
    let wide = devicePanelWidth(state(device: 0.45, action: 0.3))
    XCTAssertGreaterThan(wide, narrow)
  }

  func testTheConfiguredShareIsRoughlyWhatIsDrawn() {
    XCTAssertEqual(Double(devicePanelWidth(state(device: 0.4, action: 0.25))), 64, accuracy: 2)
  }

  /// No setting must draw exactly what it drew before the setting existed.
  func testTheDefaultIsUnchanged() {
    let configured = devicePanelWidth(state(device: nil, action: nil))
    XCTAssertEqual(configured, 34)
  }

  /// The activity panel must survive two greedy side panels.
  func testTheActivityPanelIsNeverSqueezedOut() {
    let screen = TUIRenderer().render(
      state: state(device: 0.6, action: 0.6), columns: 100, rows: 30)
    XCTAssertFalse(screen.isEmpty)
    let plain = screen.replacingOccurrences(
      of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    // Three panels are still drawn rather than two, so nothing was starved out.
    let row = plain.components(separatedBy: "\r\n").first { $0.contains("Devices") } ?? ""
    XCTAssertTrue(row.contains("Actions"))
  }
}
