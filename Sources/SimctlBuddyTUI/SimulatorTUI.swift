import Foundation
import SimctlBuddyCore

public final class SimulatorTUI {
  private let client: SimctlClient
  private let linkStore: LinkStore
  private let terminal: TerminalSession
  private let renderer: TUIRenderer
  private var state = TUIState()
  private var shouldQuit = false

  public init(
    client: SimctlClient = SimctlClient(),
    linkStore: LinkStore = LinkStore()
  ) {
    self.client = client
    self.linkStore = linkStore
    terminal = TerminalSession()
    renderer = TUIRenderer()
  }

  public func run() throws {
    try terminal.start()
    defer { terminal.stop() }

    refresh(message: "Welcome. Select a simulator and an action.")
    var lastSize = terminal.size()
    draw()
    while !shouldQuit {
      if let key = terminal.readKey() {
        handle(key)
        if !shouldQuit { draw() }
      } else {
        let size = terminal.size()
        if size != lastSize {
          lastSize = size
          draw()
        }
      }
    }
  }

  private func draw() {
    let size = terminal.size()
    terminal.write(renderer.render(state: state, columns: size.columns, rows: size.rows))
  }

  private func handle(_ key: TerminalKey) {
    if state.prompt != nil {
      handlePrompt(key)
      return
    }

    if state.showingHelp {
      if key == .text("q") {
        shouldQuit = true
      } else if key == .escape || key == .text("?") {
        state.showingHelp = false
      }
      return
    }

    switch key {
    case .up, .text("k"):
      state.moveSelection(by: -1)
    case .down, .text("j"):
      state.moveSelection(by: 1)
    case .left, .text("h"):
      state.focus = .devices
    case .right, .text("l"):
      state.focus = .actions
    case .tab:
      state.toggleFocus()
    case .enter:
      if state.focus == .devices {
        state.focus = .actions
      } else {
        runSelectedAction()
      }
    case .text("q"):
      shouldQuit = true
    case .text("?"):
      state.showingHelp = true
    case .text("o"):
      beginPrompt(.deepLink, label: "URL")
    case .text("a"):
      beginPrompt(.savedLinkName, label: "Name")
    case .text("e"):
      editSelectedSavedLink()
    case .text("b"):
      execute(.boot)
    case .text("x"):
      execute(.shutdown)
    case .text("i"):
      beginPrompt(.installApp, label: "Path to .app")
    case .text("L"):
      beginPrompt(.launchApp, label: "Bundle identifier")
    case .text("t"):
      beginPrompt(.terminateApp, label: "Bundle identifier")
    case .text("s"):
      execute(.screenshot)
    case .text("c"):
      beginPrompt(.clipboard, label: "Text to copy")
    case .text("g"):
      beginPrompt(.location, label: "Latitude,longitude")
    case .text("r"):
      execute(.refresh)
    case .escape, .backspace, .clearLine, .text:
      break
    }
  }

  private func handlePrompt(_ key: TerminalKey) {
    guard var prompt = state.prompt else { return }
    switch key {
    case .escape:
      state.prompt = nil
      appendOutput("Cancelled")
    case .enter:
      state.prompt = nil
      submit(prompt)
    case .backspace:
      if !prompt.value.isEmpty { prompt.value.removeLast() }
      state.prompt = prompt
    case .clearLine:
      prompt.value = ""
      state.prompt = prompt
    case .text(let value):
      prompt.value.append(value)
      state.prompt = prompt
    case .up, .down, .left, .right, .tab:
      break
    }
  }

  private func runSelectedAction() {
    let actions = state.actions
    guard actions.indices.contains(state.selectedActionIndex) else { return }
    let action = actions[state.selectedActionIndex].id
    switch action {
    case .openDeepLink:
      beginPrompt(.deepLink, label: "URL")
    case .addSavedLink:
      beginPrompt(.savedLinkName, label: "Name")
    case .installApp:
      beginPrompt(.installApp, label: "Path to .app")
    case .launchApp:
      beginPrompt(.launchApp, label: "Bundle identifier")
    case .terminateApp:
      beginPrompt(.terminateApp, label: "Bundle identifier")
    case .clipboard:
      beginPrompt(.clipboard, label: "Text to copy")
    case .location:
      beginPrompt(.location, label: "Latitude,longitude")
    default:
      execute(action)
    }
  }

  private func beginPrompt(_ kind: TUIPromptKind, label: String, value: String = "") {
    state.prompt = TUIPrompt(kind: kind, label: label, value: value)
  }

  private func editSelectedSavedLink() {
    guard case .savedLink(let link) = state.selectedAction?.id else {
      appendOutput("Select a saved deep link, then press e to edit it", error: true)
      return
    }
    beginPrompt(.editSavedLinkURL(name: link.name), label: "URL", value: link.url)
  }

  private func submit(_ prompt: TUIPrompt) {
    let value = prompt.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      appendOutput("Nothing entered")
      return
    }

    switch prompt.kind {
    case .deepLink:
      performOnBootedDevice { device in
        try client.openURL(value, device: device)
        return "Opened \(value)"
      }
    case .savedLinkName:
      beginPrompt(.savedLinkURL(name: value), label: "URL")
    case .savedLinkURL(let name), .editSavedLinkURL(let name):
      perform {
        try linkStore.add(name: name, url: value, force: true)
        refresh(message: "Saved deep link \(name) → \(value)")
      }
    case .installApp:
      performOnBootedDevice { device in
        let path = try client.validateAppBundle(at: value)
        _ = try client.simctl(["install", device.udid, path])
        return "Installed \(URL(fileURLWithPath: path).lastPathComponent)"
      }
    case .launchApp:
      performOnBootedDevice { device in
        let result = try client.simctl(["launch", device.udid, value])
        return result.isEmpty ? "Launched \(value)" : "Launched \(value) · \(result)"
      }
    case .terminateApp:
      performOnBootedDevice { device in
        _ = try client.simctl(["terminate", device.udid, value])
        return "Terminated \(value)"
      }
    case .clipboard:
      performOnBootedDevice { device in
        _ = try client.simctl(["pbcopy", device.udid], standardInput: Data(value.utf8))
        return "Copied text to simulator clipboard"
      }
    case .location:
      setLocation(value)
    }
  }

  private func execute(_ action: TUIActionID) {
    switch action {
    case .savedLink(let link):
      performOnBootedDevice { device in
        try client.openURL(link.url, device: device)
        return "Opened \(link.name) → \(link.url)"
      }
    case .boot:
      guard let selected = state.selectedDevice else {
        appendOutput("No simulator selected", error: true)
        return
      }
      perform {
        let device = try client.boot(selector: selected.udid)
        refresh(message: "\(device.name) is ready")
      }
    case .shutdown:
      performOnBootedDevice { device in
        _ = try client.simctl(["shutdown", device.udid])
        return "Shut down \(device.name)"
      } completion: {
        self.refresh(message: "Simulator shut down")
      }
    case .screenshot:
      performOnBootedDevice { device in
        let name = "simbuddy-\(Self.timestamp()).png"
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
          .appendingPathComponent(name).path
        _ = try client.simctl(["io", device.udid, "screenshot", path])
        return "Screenshot saved to \(path)"
      }
    case .appearanceDark:
      setAppearance("dark")
    case .appearanceLight:
      setAppearance("light")
    case .cleanStatusBar:
      performOnBootedDevice { device in
        _ = try client.simctl([
          "status_bar", device.udid, "override", "--time", "9:41",
          "--batteryState", "charged", "--batteryLevel", "100",
          "--wifiBars", "3", "--cellularBars", "4",
        ])
        return "Applied clean 9:41 status bar"
      }
    case .clearStatusBar:
      performOnBootedDevice { device in
        _ = try client.simctl(["status_bar", device.udid, "clear"])
        return "Cleared status-bar override"
      }
    case .refresh:
      refresh(message: "Refreshed devices")
    case .openDeepLink, .addSavedLink, .installApp, .launchApp, .terminateApp, .clipboard,
      .location:
      break
    }
  }

  private func setAppearance(_ appearance: String) {
    performOnBootedDevice { device in
      _ = try client.simctl(["ui", device.udid, "appearance", appearance])
      return "Switched to \(appearance) appearance"
    }
  }

  private func setLocation(_ value: String) {
    let parts = value.split(separator: ",").map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard
      parts.count == 2,
      let latitude = Double(parts[0]),
      let longitude = Double(parts[1])
    else {
      appendOutput("Use latitude,longitude — for example 46.0569,14.5058", error: true)
      return
    }

    performOnBootedDevice { device in
      try client.validateCoordinate(latitude: latitude, longitude: longitude)
      _ = try client.simctl(["location", device.udid, "set", "\(latitude),\(longitude)"])
      return "Set location to \(latitude),\(longitude)"
    }
  }

  private func performOnBootedDevice(
    _ operation: (SimulatorDevice) throws -> String,
    completion: (() -> Void)? = nil
  ) {
    guard let device = state.selectedDevice else {
      appendOutput("No simulator selected", error: true)
      return
    }
    guard device.isBooted else {
      appendOutput(
        "\(device.name) is shut down. Choose “Boot / show simulator” first.", error: true)
      return
    }
    perform {
      let message = try operation(device)
      appendOutput(message)
      completion?()
    }
  }

  private func perform(_ operation: () throws -> Void) {
    do {
      appendOutput("Working…")
      draw()
      try operation()
    } catch {
      appendOutput(error.localizedDescription, error: true)
    }
  }

  private func refresh(message: String? = nil) {
    let previousUDID = state.selectedDevice?.udid
    do {
      state.devices = try client.devices()
      state.links = (try? linkStore.load()) ?? []
      if let previousUDID, let index = state.devices.firstIndex(where: { $0.udid == previousUDID })
      {
        state.selectedDeviceIndex = index
      }
      state.clampSelections()
      if let message { appendOutput(message) }
    } catch {
      appendOutput(error.localizedDescription, error: true)
    }
  }

  private func appendOutput(_ message: String, error: Bool = false) {
    let prefix = error ? "✗" : "✓"
    state.output.insert("\(prefix) \(message)", at: 0)
    state.output = Array(state.output.prefix(12))
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }
}
