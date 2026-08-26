import Foundation
import SimctlBuddyCore

/// What a background job produced: a plain message, or a message plus a request
/// to reload devices and saved links.
private enum JobOutcome: Sendable {
  case message(String)
  case report(String, details: [String])
  case installed([String])
  case reload(String?)
}

private struct JobResult: Sendable {
  var message: String?
  var details: [String] = []
  var installedApps: [String]?
  var isError = false
  var devices: [SimulatorDevice]?
  var links: [SavedLink]?
  var apps: [SavedApp]?
}

/// Hands results from the simctl queue back to the render loop.
private final class JobMailbox: @unchecked Sendable {
  private let lock = NSLock()
  private var results: [JobResult] = []

  func post(_ result: JobResult) {
    lock.lock()
    results.append(result)
    lock.unlock()
  }

  func drain() -> [JobResult] {
    lock.lock()
    defer { lock.unlock() }
    let pending = results
    results.removeAll()
    return pending
  }
}

public final class SimulatorTUI {
  private let client: SimctlClient
  private let linkStore: LinkStore
  private let appStore: AppStore
  private let terminal: TerminalSession
  private let renderer: TUIRenderer
  private var state = TUIState()
  private var shouldQuit = false
  private let mailbox = JobMailbox()
  private let jobQueue = DispatchQueue(label: "com.simctlbuddy.simctl")

  public init(
    client: SimctlClient = SimctlClient(),
    linkStore: LinkStore = LinkStore(),
    appStore: AppStore = AppStore()
  ) {
    self.client = client
    self.linkStore = linkStore
    self.appStore = appStore
    terminal = TerminalSession()
    renderer = TUIRenderer()
  }

  public func run() throws {
    try terminal.start()
    defer { terminal.stop() }

    reloadEverything(message: "Welcome. Select a simulator and an action.")
    var lastSize = terminal.size()
    draw()
    // readKey returns after a short timeout, which doubles as the animation and
    // job-polling tick so simctl never blocks the interface.
    while !shouldQuit {
      var needsDraw = false
      if let key = terminal.readKey() {
        handle(key)
        needsDraw = true
      }
      if applyFinishedJobs() { needsDraw = true }
      if state.busy != nil {
        state.spinnerFrame += 1
        needsDraw = true
      }
      let size = terminal.size()
      if size != lastSize {
        lastSize = size
        needsDraw = true
      }
      if needsDraw && !shouldQuit { draw() }
    }
  }

  private func startJob(
    _ label: String,
    _ operation: @escaping @Sendable () throws -> JobOutcome
  ) {
    if let running = state.busy {
      appendOutput("\(running) is still running", error: true)
      return
    }
    state.busy = label
    state.spinnerFrame = 0

    let mailbox = self.mailbox
    let client = self.client
    let linkStore = self.linkStore
    let appStore = self.appStore
    jobQueue.async {
      var result = JobResult()
      var reload = false
      do {
        switch try operation() {
        case .message(let text):
          result.message = text
        case .report(let text, let details):
          result.message = text
          result.details = details
        case .installed(let identifiers):
          result.installedApps = identifiers
        case .reload(let text):
          result.message = text
          reload = true
        }
      } catch {
        result.message = error.localizedDescription
        result.isError = true
      }
      if reload {
        result.devices = try? client.devices()
        result.links = try? linkStore.load()
        result.apps = try? appStore.load()
      }
      mailbox.post(result)
    }
  }

  private func applyFinishedJobs() -> Bool {
    let results = mailbox.drain()
    guard !results.isEmpty else { return false }
    for result in results {
      if let devices = result.devices { applyDevices(devices) }
      if let links = result.links { state.links = links }
      if let apps = result.apps { state.apps = apps }
      if let installed = result.installedApps { applyInstalledApps(installed) }
      if let message = result.message {
        appendReport(message, details: result.details, error: result.isError)
      }
    }
    state.busy = nil
    state.clampSelections()
    return true
  }

  private func applyInstalledApps(_ identifiers: [String]) {
    state.installedApps = identifiers
    guard var picker = state.picker else { return }
    let known = Set(picker.options.map(\.value))
    picker.options += identifiers.filter { !known.contains($0) }
      .map { TUIPickerOption(value: $0, label: $0, detail: "installed") }
    picker.isLoading = false
    state.picker = picker
  }

  private func applyDevices(_ devices: [SimulatorDevice]) {
    let previousUDID = state.selectedDevice?.udid
    state.devices = devices
    if let previousUDID,
      let index = state.visibleDevices.firstIndex(where: { $0.udid == previousUDID })
    {
      state.selectedDeviceIndex = index
    }
  }

  private func reloadEverything(message: String?) {
    startJob("Loading simulators") { .reload(message) }
  }

  private func draw() {
    let size = terminal.size()
    terminal.write(renderer.render(state: state, columns: size.columns, rows: size.rows))
  }

  private func handle(_ key: TerminalKey) {
    if key == .interrupt {
      shouldQuit = true
      return
    }

    if state.picker != nil {
      handlePicker(key)
      return
    }

    if state.prompt != nil {
      handlePrompt(key)
      return
    }

    if state.filtering {
      handleFilter(key)
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
    case .text("+"):
      state.growFocusedPanel()
    case .text("-"), .text("_"):
      state.shrinkFocusedPanel()
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
    case .text("/"):
      state.filtering = true
      state.resetFocusedSelection()
    case .text("o"):
      beginPrompt(.deepLink, label: "URL")
    case .text("a"):
      beginPrompt(.savedLinkName, label: "Name")
    case .text("e"):
      editSelectedEntry()
    case .text("d"):
      removeSelectedEntry()
    case .text("p"):
      beginPrompt(.pushBundle, label: "Bundle identifier")
    case .text("v"):
      execute(.clipboardPaste)
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
    case .escape:
      if !state.activeFilter.isEmpty {
        state.clearActiveFilter()
      }
    case .backspace, .clearLine, .text, .interrupt:
      break
    }
  }

  /// Opens a bundle-identifier picker seeded with saved apps, then fetches the
  /// apps installed on the selected device in the background.
  private func openBundlePicker(_ purpose: TUIPickerPurpose, title: String) {
    guard let device = bootedSelection() else { return }
    let saved = state.apps.map {
      TUIPickerOption(value: $0.bundleIdentifier, label: $0.name, detail: $0.bundleIdentifier)
    }
    let cached = state.installedApps.filter { identifier in
      !saved.contains { $0.value == identifier }
    }
    .map { TUIPickerOption(value: $0, label: $0, detail: "installed") }

    state.picker = TUIPicker(
      purpose: purpose,
      title: title,
      options: saved + cached,
      isLoading: true
    )
    let client = self.client
    startJob("Reading installed apps") {
      .installed(try client.installedBundleIdentifiers(device: device))
    }
  }

  private func handlePicker(_ key: TerminalKey) {
    guard var picker = state.picker else { return }
    switch key {
    case .interrupt:
      shouldQuit = true
      return
    case .escape:
      state.picker = nil
      appendOutput("Cancelled")
      return
    case .enter:
      guard let option = picker.selectedOption else {
        appendOutput("Nothing selected", error: true)
        return
      }
      state.picker = nil
      choose(option.value, for: picker.purpose)
      return
    case .tab:
      // Escape hatch for an app that is not installed yet.
      state.picker = nil
      promptForRawBundleIdentifier(picker.purpose)
      return
    case .up:
      picker.moveSelection(by: -1)
    case .down:
      picker.moveSelection(by: 1)
    case .backspace:
      if !picker.query.isEmpty {
        picker.query.removeLast()
        picker.selectedIndex = 0
      }
    case .clearLine:
      picker.query = ""
      picker.selectedIndex = 0
    case .text(let value):
      picker.query.append(value)
      picker.selectedIndex = 0
    case .left, .right:
      break
    }
    state.picker = picker
  }

  private func promptForRawBundleIdentifier(_ purpose: TUIPickerPurpose) {
    switch purpose {
    case .launchApp: beginPrompt(.launchApp, label: "Bundle identifier")
    case .terminateApp: beginPrompt(.terminateApp, label: "Bundle identifier")
    case .pushBundle: beginPrompt(.pushBundle, label: "Bundle identifier")
    case .privacyBundle(let action, let service):
      beginPrompt(.privacyBundle(action: action, service: service), label: "Bundle identifier")
    case .privacyResetBundle: beginPrompt(.privacyResetBundle, label: "Bundle identifier")
    case .saveApp: beginPrompt(.savedAppName(bundleIdentifier: ""), label: "Bundle identifier")
    }
  }

  private func choose(_ bundleIdentifier: String, for purpose: TUIPickerPurpose) {
    switch purpose {
    case .launchApp:
      launch(bundleIdentifier)
    case .terminateApp:
      terminate(bundleIdentifier)
    case .pushBundle:
      beginPrompt(.pushPayload(bundleIdentifier: bundleIdentifier), label: "Path to .apns payload")
    case .privacyBundle(let action, let service):
      changePrivacy(action, service: service, bundleIdentifier: bundleIdentifier)
    case .privacyResetBundle:
      resetPrivacy(bundleIdentifier)
    case .saveApp:
      beginPrompt(.savedAppName(bundleIdentifier: bundleIdentifier), label: "Name for this app")
    }
  }

  private func launch(_ bundleIdentifier: String) {
    onBootedDevice("Launching \(bundleIdentifier)") { device, client in
      let result = try client.simctl(["launch", device.udid, bundleIdentifier])
      return result.isEmpty
        ? "Launched \(bundleIdentifier)" : "Launched \(bundleIdentifier) · \(result)"
    }
  }

  private func terminate(_ bundleIdentifier: String) {
    onBootedDevice("Terminating \(bundleIdentifier)") { device, client in
      _ = try client.simctl(["terminate", device.udid, bundleIdentifier])
      return "Terminated \(bundleIdentifier)"
    }
  }

  private func changePrivacy(
    _ action: TUIPrivacyAction, service: String, bundleIdentifier: String
  ) {
    let verb = action == .grant ? "Granted" : "Revoked"
    onBootedDevice("\(action.rawValue.capitalized)ing \(service)") { device, client in
      _ = try client.simctl([
        "privacy", device.udid, action.rawValue, service, bundleIdentifier,
      ])
      return "\(verb) \(service) for \(bundleIdentifier)"
    }
  }

  private func resetPrivacy(_ bundleIdentifier: String) {
    onBootedDevice("Resetting privacy for \(bundleIdentifier)") { device, client in
      _ = try client.simctl(["privacy", device.udid, "reset", "all", bundleIdentifier])
      return "Reset privacy permissions for \(bundleIdentifier)"
    }
  }

  private func handleFilter(_ key: TerminalKey) {
    switch key {
    case .escape:
      state.clearActiveFilter()
      state.filtering = false
    case .enter:
      state.filtering = false
    case .backspace:
      if !state.activeFilter.isEmpty {
        state.activeFilter.removeLast()
        state.resetFocusedSelection()
      }
    case .clearLine:
      state.clearActiveFilter()
    case .up:
      state.moveSelection(by: -1)
    case .down:
      state.moveSelection(by: 1)
    case .text(let value):
      state.activeFilter.append(value)
      state.resetFocusedSelection()
    case .tab:
      // Committing on Tab is friendlier than swallowing the key.
      state.filtering = false
      state.toggleFocus()
    case .left, .right, .interrupt:
      break
    }
    state.clampSelections()
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
    case .up, .down, .left, .right, .tab, .interrupt:
      break
    }
  }

  private func runSelectedAction() {
    guard let action = state.selectedAction?.id else { return }
    switch action {
    case .openDeepLink:
      beginPrompt(.deepLink, label: "URL")
    case .addSavedLink:
      beginPrompt(.savedLinkName, label: "Name")
    case .installApp:
      beginPrompt(.installApp, label: "Path to .app")
    case .launchApp:
      openBundlePicker(.launchApp, title: "Launch app")
    case .terminateApp:
      openBundlePicker(.terminateApp, title: "Terminate app")
    case .clipboard:
      beginPrompt(.clipboard, label: "Text to copy")
    case .location:
      beginPrompt(.location, label: "Latitude,longitude")
    case .push:
      openBundlePicker(.pushBundle, title: "Send push · pick an app")
    case .privacy(let privacyAction):
      beginPrompt(.privacyService(action: privacyAction), label: "Service")
    case .privacyReset:
      openBundlePicker(.privacyResetBundle, title: "Reset privacy · pick an app")
    case .saveApp:
      openBundlePicker(.saveApp, title: "Save app bundle ID")
    default:
      execute(action)
    }
  }

  private func removeSelectedEntry() {
    switch state.selectedAction?.id {
    case .savedLink(let link):
      beginPrompt(
        .confirmRemoveSavedLink(name: link.name),
        label: "Delete “\(link.name)” → \(link.url)?")
    case .savedApp(let app):
      beginPrompt(
        .confirmRemoveSavedApp(name: app.name),
        label: "Delete “\(app.name)” → \(app.bundleIdentifier)?")
    default:
      appendOutput("Select a saved deep link or app, then press d to delete it", error: true)
    }
  }

  private func beginPrompt(_ kind: TUIPromptKind, label: String, value: String = "") {
    state.prompt = TUIPrompt(kind: kind, label: label, value: value)
  }

  private func editSelectedEntry() {
    switch state.selectedAction?.id {
    case .savedLink(let link):
      beginPrompt(.editSavedLinkURL(name: link.name), label: "URL", value: link.url)
    case .savedApp(let app):
      beginPrompt(
        .editSavedAppBundle(name: app.name), label: "Bundle identifier",
        value: app.bundleIdentifier)
    default:
      appendOutput("Select a saved deep link or app, then press e to edit it", error: true)
    }
  }

  private func submit(_ prompt: TUIPrompt) {
    let value = prompt.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty || prompt.kind.isConfirmation else {
      appendOutput("Nothing entered")
      return
    }

    switch prompt.kind {
    case .deepLink:
      onBootedDevice("Opening deep link") { device, client in
        try client.openURL(value, device: device)
        return "Opened \(value)"
      }
    case .savedLinkName:
      beginPrompt(.savedLinkURL(name: value), label: "URL")
    case .savedLinkURL(let name), .editSavedLinkURL(let name):
      let store = linkStore
      startJob("Saving deep link") {
        try store.add(name: name, url: value, force: true)
        return .reload("Saved deep link \(name) → \(value)")
      }
    case .installApp:
      onBootedDevice("Installing app") { device, client in
        let path = try client.validateAppBundle(at: value)
        _ = try client.simctl(["install", device.udid, path])
        return "Installed \(URL(fileURLWithPath: path).lastPathComponent)"
      }
    case .launchApp:
      launch(value)
    case .terminateApp:
      terminate(value)
    case .clipboard:
      onBootedDevice("Copying to clipboard") { device, client in
        _ = try client.simctl(["pbcopy", device.udid], standardInput: Data(value.utf8))
        return "Copied text to simulator clipboard"
      }
    case .location:
      setLocation(value)
    case .pushBundle:
      beginPrompt(.pushPayload(bundleIdentifier: value), label: "Path to .apns payload")
    case .pushPayload(let bundleIdentifier):
      onBootedDevice("Sending push to \(bundleIdentifier)") { device, client in
        let path = try client.validateFile(at: value)
        _ = try client.simctl(["push", device.udid, bundleIdentifier, path])
        return "Sent push notification to \(bundleIdentifier)"
      }
    case .privacyService(let action):
      openBundlePicker(
        .privacyBundle(action: action, service: value),
        title: "\(action.rawValue.capitalized) \(value) · pick an app")
    case .privacyBundle(let action, let service):
      changePrivacy(action, service: service, bundleIdentifier: value)
    case .privacyResetBundle:
      resetPrivacy(value)
    case .confirmRemoveSavedLink(let name):
      let store = linkStore
      startJob("Deleting \(name)") {
        try store.remove(name: name)
        return .reload("Deleted saved deep link \(name)")
      }
    case .savedAppName(let bundleIdentifier):
      // Reached with an empty identifier when the picker was bypassed with Tab.
      guard !bundleIdentifier.isEmpty else {
        beginPrompt(.savedAppName(bundleIdentifier: value), label: "Name for this app")
        return
      }
      saveApp(name: value, bundleIdentifier: bundleIdentifier)
    case .editSavedAppBundle(let name):
      saveApp(name: name, bundleIdentifier: value)
    case .confirmRemoveSavedApp(let name):
      let store = appStore
      startJob("Deleting \(name)") {
        try store.remove(name: name)
        return .reload("Deleted saved app \(name)")
      }
    }
  }

  private func saveApp(name: String, bundleIdentifier: String) {
    let store = appStore
    startJob("Saving \(name)") {
      try store.add(name: name, bundleIdentifier: bundleIdentifier, force: true)
      return .reload("Saved app \(name) → \(bundleIdentifier)")
    }
  }

  private func execute(_ action: TUIActionID) {
    switch action {
    case .savedApp(let app):
      launch(app.bundleIdentifier)
    case .saveApp:
      openBundlePicker(.saveApp, title: "Save app bundle ID")
    case .savedLink(let link):
      onBootedDevice("Opening \(link.name)") { device, client in
        try client.openURL(link.url, device: device)
        return "Opened \(link.name) → \(link.url)"
      }
    case .boot:
      guard let selected = state.selectedDevice else {
        appendOutput("No simulator selected", error: true)
        return
      }
      let client = self.client
      startJob("Booting \(selected.name)") {
        let device = try client.boot(selector: selected.udid)
        return .reload("\(device.name) is ready")
      }
    case .shutdown:
      onBootedDevice("Shutting down", reload: true) { device, client in
        _ = try client.simctl(["shutdown", device.udid])
        return "Shut down \(device.name)"
      }
    case .screenshot:
      onBootedDevice("Capturing screenshot") { device, client in
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
      onBootedDevice("Applying status bar") { device, client in
        _ = try client.simctl([
          "status_bar", device.udid, "override", "--time", "9:41",
          "--batteryState", "charged", "--batteryLevel", "100",
          "--wifiBars", "3", "--cellularBars", "4",
        ])
        return "Applied clean 9:41 status bar"
      }
    case .clearStatusBar:
      onBootedDevice("Clearing status bar") { device, client in
        _ = try client.simctl(["status_bar", device.udid, "clear"])
        return "Cleared status-bar override"
      }
    case .listApps:
      onBootedDeviceReporting("Listing installed apps") { device, client in
        let identifiers = try client.installedBundleIdentifiers(device: device)
        guard !identifiers.isEmpty else {
          return .message("No apps are installed on \(device.name)")
        }
        return .report("\(identifiers.count) apps installed", details: identifiers)
      }
    case .push:
      beginPrompt(.pushBundle, label: "Bundle identifier")
    case .privacy(let privacyAction):
      beginPrompt(.privacyService(action: privacyAction), label: "Service")
    case .privacyReset:
      beginPrompt(.privacyResetBundle, label: "Bundle identifier")
    case .clipboardPaste:
      onBootedDevice("Reading simulator clipboard") { device, client in
        let contents = try client.simctl(["pbpaste", device.udid])
        guard !contents.isEmpty else { return "The simulator clipboard is empty" }
        // A whole clipboard can be enormous; keep the log usable.
        let limit = 200
        let shown =
          contents.count > limit ? String(contents.prefix(limit)) + "…" : contents
        return "Simulator clipboard: \(shown)"
      }
    case .locationClear:
      onBootedDevice("Clearing location") { device, client in
        _ = try client.simctl(["location", device.udid, "clear"])
        return "Cleared simulated location on \(device.name)"
      }
    case .doctor:
      let client = self.client
      startJob("Running diagnostics") {
        .report("Diagnostics passed", details: try client.diagnostics())
      }
    case .refresh:
      reloadEverything(message: "Refreshed devices")
    case .openDeepLink, .addSavedLink, .installApp, .launchApp, .terminateApp, .clipboard,
      .location:
      break
    }
  }

  private func setAppearance(_ appearance: String) {
    onBootedDevice("Switching appearance") { device, client in
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

    onBootedDevice("Setting location") { device, client in
      try client.validateCoordinate(latitude: latitude, longitude: longitude)
      _ = try client.simctl(["location", device.udid, "set", "\(latitude),\(longitude)"])
      return "Set location to \(latitude),\(longitude)"
    }
  }

  private func onBootedDeviceReporting(
    _ label: String,
    _ operation: @escaping @Sendable (SimulatorDevice, SimctlClient) throws -> JobOutcome
  ) {
    guard let device = bootedSelection() else { return }
    let client = self.client
    startJob(label) { try operation(device, client) }
  }

  private func bootedSelection() -> SimulatorDevice? {
    guard let device = state.selectedDevice else {
      appendOutput("No simulator selected", error: true)
      return nil
    }
    guard device.isBooted else {
      appendOutput(
        "\(device.name) is shut down. Choose “Boot / show simulator” first.", error: true)
      return nil
    }
    return device
  }

  private func onBootedDevice(
    _ label: String,
    reload: Bool = false,
    _ operation: @escaping @Sendable (SimulatorDevice, SimctlClient) throws -> String
  ) {
    guard let device = bootedSelection() else { return }
    let client = self.client
    startJob(label) {
      let message = try operation(device, client)
      return reload ? .reload(message) : .message(message)
    }
  }

  private func appendOutput(_ message: String, error: Bool = false) {
    appendReport(message, details: [], error: error)
  }

  /// Newest entries sit at the top, so detail lines go in before their headline
  /// to keep the block reading top-down.
  private func appendReport(_ message: String, details: [String], error: Bool) {
    for line in details.reversed() {
      state.output.insert("  \(line)", at: 0)
    }
    state.output.insert("\(error ? "✗" : "✓") \(message)", at: 0)
    state.output = Array(state.output.prefix(60))
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }
}
