import Foundation
import SimctlBuddyCore

/// What a background job produced: a plain message, or a message plus a request
/// to reload devices and saved links.
private enum JobOutcome: Sendable {
  case message(String)
  case report(String, details: [String])
  case installed([String])
  /// Options for the picker that is already on screen.
  case pickerOptions([TUIPickerOption], message: String? = nil)
  case reload(String?, details: [String] = [])
}

private struct JobResult: Sendable {
  var message: String?
  var details: [String] = []
  var installedApps: [String]?
  var pickerOptions: [TUIPickerOption]?
  var isError = false
  var devices: [SimulatorDevice]?
  var links: [SavedLink]?
  var apps: [SavedApp]?
  var paths: [SavedPath]?
  var recentPaths: [String]?
  var firebaseApps: [SavedFirebaseApp]?
  var settings: Settings?
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
  private let service: DeviceService
  private let linkStore: LinkStore
  private let appStore: AppStore
  private let pathStore: PathStore
  private let firebaseStore: FirebaseStore
  private let settingsStore: SettingsStore
  private let valueStore: LinkValueStore
  private let recorder: Recorder
  private let completer: PathCompleter
  private let terminal: TerminalSession
  private var renderer: TUIRenderer
  private var state = TUIState()
  private var shouldQuit = false
  private let mailbox = JobMailbox()
  private let jobQueue = DispatchQueue(label: "com.simctlbuddy.simctl")

  public init(
    client: SimctlClient = SimctlClient(),
    service: DeviceService? = nil,
    linkStore: LinkStore = LinkStore(),
    appStore: AppStore = AppStore(),
    pathStore: PathStore = PathStore(),
    firebaseStore: FirebaseStore = FirebaseStore(),
    settingsStore: SettingsStore = SettingsStore(),
    valueStore: LinkValueStore = LinkValueStore(),
    recorder: Recorder = Recorder(),
    completer: PathCompleter = PathCompleter()
  ) {
    self.client = client
    self.service = service ?? DeviceService(simctl: client)
    self.linkStore = linkStore
    self.appStore = appStore
    self.pathStore = pathStore
    self.firebaseStore = firebaseStore
    self.settingsStore = settingsStore
    self.valueStore = valueStore
    self.recorder = recorder
    self.completer = completer
    terminal = TerminalSession()
    renderer = TUIRenderer()
  }

  public func run() throws {
    try terminal.start()
    defer { terminal.stop() }
    // Quitting mid-recording would otherwise orphan simctl and lose the movie.
    defer { recorder.cancel() }

    // Ask the terminal how wide it draws the glyphs this interface is made of,
    // before anything is drawn with them.
    let ambiguousWidth = terminal.measureAmbiguousWidth()
    renderer = TUIRenderer(metrics: DisplayMetrics(ambiguousWidth: ambiguousWidth))

    reloadEverything(message: "Welcome. Select a device and an action.")
    if ambiguousWidth == 2 {
      // Worth saying out loud: it explains the ASCII frame, and confirms the
      // measurement if the layout ever looks wrong again.
      appendOutput(
        "This terminal draws box glyphs double width, so the frame is ASCII")
    }
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
      // The header counts the recording up, so it needs a tick of its own.
      if state.recording != nil { needsDraw = true }
      let size = terminal.size()
      if size != lastSize {
        lastSize = size
        terminal.clear()
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
    let service = self.service
    let linkStore = self.linkStore
    let appStore = self.appStore
    let pathStore = self.pathStore
    let firebaseStore = self.firebaseStore
    let settingsStore = self.settingsStore
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
        case .pickerOptions(let options, let message):
          result.pickerOptions = options
          result.message = message
        case .reload(let text, let extra):
          result.message = text
          result.details = extra
          reload = true
        }
      } catch {
        result.message = error.localizedDescription
        result.isError = true
      }
      if reload {
        // Physical devices are best effort: a missing devicectl must not empty
        // the list.
        result.devices = try? service.devices()
        result.links = try? linkStore.load()
        result.apps = try? appStore.load()
        let book = try? pathStore.load()
        result.paths = book?.saved
        result.recentPaths = book?.recent
        result.firebaseApps = try? firebaseStore.load()
        result.settings = try? settingsStore.load()
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
      if let paths = result.paths { state.paths = paths }
      if let recentPaths = result.recentPaths { state.recentPaths = recentPaths }
      if let firebaseApps = result.firebaseApps { state.firebaseApps = firebaseApps }
      if let settings = result.settings { state.settings = settings }
      if let installed = result.installedApps { applyInstalledApps(installed) }
      if let options = result.pickerOptions { applyPickerOptions(options) }
      if let message = result.message {
        appendReport(message, details: result.details, error: result.isError)
      }
    }
    state.busy = nil
    // The recorder owns the truth about whether a recording is live.
    state.recording = recorder.session
    state.clampSelections()
    return true
  }

  /// Fills in a picker whose contents had to be read from the device.
  private func applyPickerOptions(_ options: [TUIPickerOption]) {
    guard var picker = state.picker else { return }
    let known = Set(picker.options.map(\.value))
    picker.options += options.filter { !known.contains($0.value) }
    picker.isLoading = false
    state.picker = picker
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
      openInstallPicker()
    case .text("f"):
      openFirebaseAppPicker()
    case .text("L"):
      beginPrompt(.launchApp, label: "Bundle identifier")
    case .text("t"):
      beginPrompt(.terminateApp, label: "Bundle identifier")
    case .text("s"):
      execute(.screenshot)
    case .text("R"):
      execute(state.isRecording ? .stopRecording : .startRecording)
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
      state.pendingLink = nil
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
    case .installPath: beginPrompt(.installApp, label: "Path to .app")
    case .savePath: beginPrompt(.savedPathValue(name: ""), label: "Path to .app")
    case .linkApp:
      appendOutput("Pick an app for this link, or press Esc", error: true)
    case .firebaseApp, .firebaseAppToSave:
      beginPrompt(.firebaseAppID, label: "Firebase app ID")
    case .firebaseRelease:
      appendOutput("Pick a build, or press Esc", error: true)
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
    case .installPath:
      install(path: bundleIdentifier)
    case .savePath:
      beginPrompt(.savedPathName(path: bundleIdentifier), label: "Name for this build")
    case .linkApp:
      chooseLinkApp(bundleIdentifier)
    case .firebaseApp:
      openFirebaseReleasePicker(appID: bundleIdentifier)
    case .firebaseAppToSave:
      beginPrompt(.firebaseAppName(appID: bundleIdentifier), label: "Name for this app")
    case .firebaseRelease(let appID):
      installFirebaseRelease(bundleIdentifier, appID: appID)
    }
  }

  /// Install without retyping a build path: saved paths first, then whatever
  /// was installed recently. Both come from state, so this needs no device call.
  private func openInstallPicker() {
    guard bootedSelection() != nil else { return }
    let saved = state.paths.map {
      TUIPickerOption(
        value: $0.path,
        label: $0.name,
        detail: $0.exists ? $0.path : "\($0.path) · missing"
      )
    }
    let savedPaths = Set(state.paths.map(\.path))
    let recent = state.recentPaths.filter { !savedPaths.contains($0) }
      .map { TUIPickerOption(value: $0, label: $0, detail: "recent") }

    guard !saved.isEmpty || !recent.isEmpty else {
      // Nothing remembered yet, so skip straight to the field.
      beginPrompt(.installApp, label: "Path to .app")
      return
    }
    state.picker = TUIPicker(
      purpose: .installPath,
      title: "Install · pick a build",
      footnote: "Saved builds first, then recently installed",
      loadingMessage: "Reading saved builds",
      options: saved + recent,
      isLoading: false
    )
  }

  /// Terminate is only ever aimed at something running, so running apps lead.
  private func openTerminatePicker() {
    guard let device = bootedSelection() else { return }
    state.picker = TUIPicker(
      purpose: .terminateApp,
      title: "Terminate app",
      footnote: "Running apps first, then everything installed",
      loadingMessage: "Reading running apps",
      options: [],
      isLoading: true
    )
    let client = self.client
    startJob("Reading running apps") {
      let running = try client.runningBundleIdentifiers(device: device)
      let installed = try client.installedBundleIdentifiers(device: device)
      let runningSet = Set(running)
      let options =
        running.map { TUIPickerOption(value: $0, label: $0, detail: "running") }
        + installed.filter { !runningSet.contains($0) }
        .map { TUIPickerOption(value: $0, label: $0, detail: "installed") }
      return .pickerOptions(
        options,
        message: running.isEmpty ? "No apps are running on \(device.name)" : nil)
    }
  }

  private func install(path: String) {
    let pathStore = self.pathStore
    onBootedDevice("Installing app", reload: true, capability: .install) { device, service in
      let bundle = try service.install(appAt: path, device: device)
      // Remembering it here is what fills the picker next time.
      try? pathStore.recordRecent(bundle.path)
      return "Installed \(bundle.name)"
    }
  }

  private func startRecording() {
    guard let device = bootedSelection() else { return }
    if let session = recorder.session {
      appendOutput("Already recording to \(session.path)", error: true)
      return
    }
    let recorder = self.recorder
    let settings = state.settings
    let path = settings.recordingDestination(fileName: CaptureName.recording())
    startJob("Starting recording") {
      let session = try recorder.start(device: device, path: path)
      return .message("Recording \(session.deviceName) to \(session.path)")
    }
  }

  private func stopRecording() {
    guard recorder.isRecording else {
      appendOutput("No recording is running", error: true)
      return
    }
    let recorder = self.recorder
    startJob("Finalizing recording") {
      let session = try recorder.stop()
      let seconds = Int(session.duration().rounded())
      return .message("Saved \(seconds)s recording to \(session.path)")
    }
  }

  private func setDirectory(_ key: SettingsKey, to value: String) {
    let store = settingsStore
    startJob("Saving preference") {
      let resolved = try store.set(key, to: value)
      return .reload("\(key.rawValue) is now \(resolved)")
    }
  }

  private func savePath(name: String, path: String) {
    let store = pathStore
    startJob("Saving \(name)") {
      try store.add(name: name, path: path, force: true)
      return .reload("Saved build \(name) → \(try PathStore.validate(path))")
    }
  }

  private func exportLinks(to path: String) {
    let store = linkStore
    startJob("Exporting deep links") {
      let destination = try store.export(to: path)
      let count = try store.load().count
      return .message("Exported \(count) deep link\(count == 1 ? "" : "s") to \(destination)")
    }
  }

  private func importLinks(from path: String) {
    let store = linkStore
    startJob("Importing deep links") {
      // Existing names are kept: an import should never silently overwrite
      // something the person already saved.
      let summary = try store.importLinks(fromFileAt: path, strategy: .skipExisting)
      var details = summary.details
      if !summary.skipped.isEmpty {
        details.append("edit a saved link with e to change it by hand")
      }
      return .reload("Imported: \(summary.headline)", details: details)
    }
  }

  /// Starts opening a deep link, collecting whatever it still needs first.
  ///
  /// A finished URL opens straight away. A template asks for the app that
  /// supplies `$scheme`, then for each parameter in turn.
  private func beginLink(name: String, url: String, apps scopedApps: [String]?) {
    guard bootedSelection() != nil else { return }
    let template = LinkTemplate.parse(url)
    let link = SavedLink(name: name, url: url, apps: scopedApps)

    guard template.isTemplate else {
      openResolvedLink(url, linkName: name, app: nil)
      return
    }

    let memory = valueStore.memory(for: name.isEmpty ? LinkValueStore.adHocKey : name)
    var pending = PendingLink(
      linkName: name,
      template: template,
      values: [:],
      remaining: template.parameters
    )

    if template.requiresScheme {
      let candidates = LinkResolver.candidates(
        for: link, apps: state.apps, installed: state.installedApps)
      guard !candidates.isEmpty else {
        appendReport(
          SimctlBuddyError.noSchemeForLink(name.isEmpty ? url : name).localizedDescription,
          details: [], error: true)
        return
      }
      guard
        let automatic = LinkResolver.automaticChoice(from: candidates, remembered: memory.app)
      else {
        // Genuinely ambiguous, so ask which app rather than guessing a market.
        state.pendingLink = pending
        openLinkAppPicker(candidates)
        return
      }
      pending.app = automatic
    }

    state.pendingLink = pending
    advanceLink()
  }

  private func openLinkAppPicker(_ candidates: [SavedApp]) {
    state.picker = TUIPicker(
      purpose: .linkApp,
      title: "Open on which app?",
      footnote: "Installed apps first · $scheme comes from the app",
      loadingMessage: "Reading saved apps",
      options: candidates.map {
        TUIPickerOption(
          value: $0.bundleIdentifier,
          label: $0.name,
          detail: $0.scheme.map { scheme in "\(scheme)://" } ?? $0.bundleIdentifier
        )
      },
      isLoading: false
    )
  }

  private func chooseLinkApp(_ bundleIdentifier: String) {
    guard var pending = state.pendingLink else { return }
    pending.app = state.apps.first {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
    state.pendingLink = pending
    advanceLink()
  }

  /// Asks for the next parameter, or opens the link once nothing is left.
  private func advanceLink() {
    guard let pending = state.pendingLink else { return }
    if let next = pending.remaining.first {
      beginPrompt(
        .linkParameter(link: pending.linkName, parameter: next.name),
        label: "Value for $\(next.name)",
        value: valueStore.startingValue(for: next, link: pending.memoryKey)
      )
      return
    }

    state.pendingLink = nil
    do {
      let url = try pending.template.render(
        scheme: pending.app?.scheme, values: pending.values)
      try? valueStore.remember(
        values: pending.values,
        app: pending.app?.bundleIdentifier,
        for: pending.memoryKey
      )
      openResolvedLink(url, linkName: pending.linkName, app: pending.app)
    } catch {
      appendReport(error.localizedDescription, details: [], error: true)
    }
  }

  private func fillLinkParameter(_ name: String, with value: String) {
    guard var pending = state.pendingLink else { return }
    pending.values[name] = value
    pending.remaining.removeAll { $0.name == name }
    state.pendingLink = pending
    advanceLink()
  }

  private func openResolvedLink(_ url: String, linkName: String, app: SavedApp?) {
    let label = linkName.isEmpty ? url : linkName
    let via = app.map { " via \($0.name)" } ?? ""
    onBootedDevice("Opening \(label)", capability: .openURL) { device, service in
      try service.openURL(url, device: device)
      return "Opened \(label) → \(url)\(via)"
    }
  }

  private func launch(_ bundleIdentifier: String) {
    onBootedDevice("Launching \(bundleIdentifier)", capability: .launch) { device, service in
      let result = try service.launch(bundleIdentifier, device: device)
      return result.isEmpty
        ? "Launched \(bundleIdentifier)" : "Launched \(bundleIdentifier) · \(result)"
    }
  }

  private func terminate(_ bundleIdentifier: String) {
    onBootedDevice("Terminating \(bundleIdentifier)", capability: .terminate) { device, service in
      try service.terminate(bundleIdentifier, device: device)
      return "Terminated \(bundleIdentifier)"
    }
  }

  private func changePrivacy(
    _ action: TUIPrivacyAction, service: String, bundleIdentifier: String
  ) {
    let verb = action == .grant ? "Granted" : "Revoked"
    onBootedDevice("\(action.rawValue.capitalized)ing \(service)", capability: .privacy) {
      device, devices in
      _ = try devices.simctl.simctl([
        "privacy", device.udid, action.rawValue, service, bundleIdentifier,
      ])
      return "\(verb) \(service) for \(bundleIdentifier)"
    }
  }

  private func resetPrivacy(_ bundleIdentifier: String) {
    onBootedDevice("Resetting privacy for \(bundleIdentifier)", capability: .privacy) {
      device, service in
      _ = try service.simctl.simctl(["privacy", device.udid, "reset", "all", bundleIdentifier])
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
      state.pendingLink = nil
      appendOutput("Cancelled")
    case .enter:
      state.prompt = nil
      submit(prompt)
    case .tab:
      // Tab means completion in a path field and nothing anywhere else.
      guard prompt.supportsCompletion else { break }
      prompt.complete(using: completer)
      state.prompt = prompt
    case .backspace:
      if !prompt.value.isEmpty { prompt.value.removeLast() }
      prompt.clearCompletion()
      state.prompt = prompt
    case .clearLine:
      prompt.value = ""
      prompt.clearCompletion()
      state.prompt = prompt
    case .text(let value):
      prompt.value.append(value)
      // A stale candidate list would describe text that is no longer there.
      prompt.clearCompletion()
      state.prompt = prompt
    case .up, .down, .left, .right, .interrupt:
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
      openInstallPicker()
    case .launchApp:
      openBundlePicker(.launchApp, title: "Launch app")
    case .terminateApp:
      openTerminatePicker()
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
    case .savePath:
      beginPrompt(.savedPathValue(name: ""), label: "Path to .app")
    case .firebaseInstall:
      openFirebaseAppPicker()
    case .saveFirebaseApp:
      openFirebaseAppBrowser()
    case .firebaseStatus:
      showFirebaseStatus()
    case .screenshotDirectory:
      beginPrompt(
        .screenshotDirectory, label: "Folder for screenshots",
        value: state.settings.screenshotDirectory ?? "")
    case .recordingDirectory:
      beginPrompt(
        .recordingDirectory, label: "Folder for recordings",
        value: state.settings.recordingDirectory ?? "")
    case .exportLinks:
      beginPrompt(.exportLinks, label: "Export to file")
    case .importLinks:
      beginPrompt(.importLinks, label: "Import from file")
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
    case .savedPath(let saved):
      beginPrompt(
        .confirmRemoveSavedPath(name: saved.name),
        label: "Delete “\(saved.name)” → \(saved.path)?")
    default:
      appendOutput(
        "Select a saved deep link, app, or build, then press d to delete it", error: true)
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
    case .savedPath(let saved):
      beginPrompt(.editSavedPath(name: saved.name), label: "Path to .app", value: saved.path)
    default:
      appendOutput(
        "Select a saved deep link, app, or build, then press e to edit it", error: true)
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
      beginLink(name: "", url: value, apps: nil)
    case .savedLinkName:
      beginPrompt(.savedLinkURL(name: value), label: "URL")
    case .savedLinkURL(let name), .editSavedLinkURL(let name):
      let store = linkStore
      startJob("Saving deep link") {
        try store.add(name: name, url: value, force: true)
        return .reload("Saved deep link \(name) → \(value)")
      }
    case .installApp:
      install(path: value)
    case .launchApp:
      launch(value)
    case .terminateApp:
      terminate(value)
    case .clipboard:
      onBootedDevice("Copying to clipboard", capability: .clipboard) { device, service in
        try service.copyToClipboard(value, device: device)
        return "Copied text to the \(device.kind.label.lowercased()) clipboard"
      }
    case .location:
      setLocation(value)
    case .pushBundle:
      beginPrompt(.pushPayload(bundleIdentifier: value), label: "Path to .apns payload")
    case .pushPayload(let bundleIdentifier):
      onBootedDevice("Sending push to \(bundleIdentifier)", capability: .push) {
        device, service in
        let path = try service.simctl.validateFile(at: value)
        _ = try service.simctl.simctl(["push", device.udid, bundleIdentifier, path])
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
      beginPrompt(
        .savedAppScheme(name: value, bundleIdentifier: bundleIdentifier),
        label: "URL scheme for \(value), or leave empty")
    case .editSavedAppBundle(let name):
      let existing = state.apps.first { $0.name == name }?.scheme
      saveApp(name: name, bundleIdentifier: value, scheme: existing)
    case .confirmRemoveSavedApp(let name):
      let store = appStore
      startJob("Deleting \(name)") {
        try store.remove(name: name)
        return .reload("Deleted saved app \(name)")
      }
    case .savedPathValue(let name):
      // Reached with an empty name when the path was typed first.
      guard !name.isEmpty else {
        beginPrompt(.savedPathName(path: value), label: "Name for this build")
        return
      }
      savePath(name: name, path: value)
    case .savedPathName(let path):
      savePath(name: value, path: path)
    case .editSavedPath(let name):
      savePath(name: name, path: value)
    case .confirmRemoveSavedPath(let name):
      let store = pathStore
      startJob("Deleting \(name)") {
        try store.remove(name: name)
        return .reload("Deleted saved build \(name)")
      }
    case .firebaseAppID:
      // Validate before asking for a name, so a typo is caught on the field it
      // was made in.
      do {
        let identifier = try FirebaseApp.validate(value)
        beginPrompt(.firebaseAppName(appID: identifier), label: "Name for this app")
      } catch {
        appendOutput(error.localizedDescription, error: true)
      }
    case .firebaseAppName(let appID):
      let store = firebaseStore
      startJob("Saving Firebase app") {
        try store.add(name: value, appID: appID, force: true)
        return .reload("Saved Firebase app \(value) \u{2192} \(appID)")
      }
    case .confirmRemoveFirebaseApp(let name):
      let store = firebaseStore
      startJob("Deleting \(name)") {
        try store.remove(name: name)
        return .reload("Deleted saved Firebase app \(name)")
      }
    case .screenshotDirectory:
      setDirectory(.screenshotDirectory, to: value)
    case .recordingDirectory:
      setDirectory(.recordingDirectory, to: value)
    case .exportLinks:
      exportLinks(to: value)
    case .importLinks:
      importLinks(from: value)
    case .savedAppScheme(let name, let bundleIdentifier):
      saveApp(name: name, bundleIdentifier: bundleIdentifier, scheme: value)
    case .linkParameter(_, let parameter):
      fillLinkParameter(parameter, with: value)
    }
  }

  private func saveApp(name: String, bundleIdentifier: String, scheme: String? = nil) {
    let store = appStore
    startJob("Saving \(name)") {
      try store.add(
        name: name, bundleIdentifier: bundleIdentifier, scheme: scheme, force: true)
      let suffix = (scheme?.isEmpty ?? true) ? "" : "  (\(scheme!)://)"
      return .reload("Saved app \(name) → \(bundleIdentifier)\(suffix)")
    }
  }

  private func execute(_ action: TUIActionID) {
    switch action {
    case .savedApp(let app):
      launch(app.bundleIdentifier)
    case .saveApp:
      openBundlePicker(.saveApp, title: "Save app bundle ID")
    case .savedPath(let saved):
      install(path: saved.path)
    case .savePath:
      beginPrompt(.savedPathValue(name: ""), label: "Path to .app")
    case .savedFirebaseApp(let app):
      openFirebaseReleasePicker(appID: app.appID)
    case .saveFirebaseApp:
      openFirebaseAppBrowser()
    case .firebaseInstall:
      openFirebaseAppPicker()
    case .firebaseStatus:
      showFirebaseStatus()
    case .savedLink(let link):
      beginLink(name: link.name, url: link.url, apps: link.apps)
    case .boot:
      guard let selected = state.selectedDevice else {
        appendOutput("No device selected", error: true)
        return
      }
      guard selected.supports(.boot) else {
        appendOutput(
          SimctlBuddyError.unsupportedAction(.boot, kind: selected.kind).localizedDescription,
          error: true)
        return
      }
      let client = self.client
      startJob("Booting \(selected.name)") {
        let device = try client.boot(selector: selected.udid)
        return .reload("\(device.name) is ready")
      }
    case .shutdown:
      onBootedDevice("Shutting down", reload: true, capability: .shutdown) { device, service in
        _ = try service.simctl.simctl(["shutdown", device.udid])
        return "Shut down \(device.name)"
      }
    case .screenshot:
      let destination = state.settings.screenshotDestination(fileName: CaptureName.screenshot())
      onBootedDevice("Capturing screenshot", capability: .screenshot) { device, service in
        // The configured folder may have been moved since it was set.
        try FileManager.default.createDirectory(
          at: URL(fileURLWithPath: destination).deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try service.screenshot(to: destination, device: device)
        return "Screenshot saved to \(destination)"
      }
    case .startRecording:
      startRecording()
    case .stopRecording:
      stopRecording()
    case .appearanceDark:
      setAppearance("dark")
    case .appearanceLight:
      setAppearance("light")
    case .cleanStatusBar:
      onBootedDevice("Applying status bar", capability: .statusBar) { device, service in
        try service.applyCleanStatusBar(device: device)
        return "Applied clean 9:41 status bar"
      }
    case .clearStatusBar:
      onBootedDevice("Clearing status bar", capability: .statusBar) { device, service in
        try service.clearStatusBar(device: device)
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
    case .listRunningApps:
      onBootedDeviceReporting("Reading running apps") { device, client in
        let identifiers = try client.runningBundleIdentifiers(device: device)
        guard !identifiers.isEmpty else {
          return .message("No apps are running on \(device.name)")
        }
        return .report("\(identifiers.count) apps running", details: identifiers)
      }
    case .push:
      beginPrompt(.pushBundle, label: "Bundle identifier")
    case .privacy(let privacyAction):
      beginPrompt(.privacyService(action: privacyAction), label: "Service")
    case .privacyReset:
      beginPrompt(.privacyResetBundle, label: "Bundle identifier")
    case .clipboardPaste:
      onBootedDevice("Reading clipboard", capability: .clipboard) { device, service in
        let contents = try service.readClipboard(device: device)
        guard !contents.isEmpty else { return "The clipboard is empty" }
        // A whole clipboard can be enormous; keep the log usable.
        let limit = 200
        let shown =
          contents.count > limit ? String(contents.prefix(limit)) + "…" : contents
        return "Clipboard: \(shown)"
      }
    case .locationClear:
      onBootedDevice("Clearing location", capability: .location) { device, service in
        try service.clearLocation(device: device)
        return "Cleared the location override on \(device.name)"
      }
    case .doctor:
      let service = self.service
      startJob("Running diagnostics") {
        .report("Diagnostics passed", details: try service.diagnostics())
      }
    case .refresh:
      reloadEverything(message: "Refreshed devices")
    case .openDeepLink, .addSavedLink, .installApp, .launchApp, .terminateApp, .clipboard,
      .location, .screenshotDirectory, .recordingDirectory, .exportLinks, .importLinks:
      break
    }
  }

  private func setAppearance(_ appearance: String) {
    onBootedDevice("Switching appearance", capability: .appearance) { device, service in
      try service.setAppearance(appearance, device: device)
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

    onBootedDevice("Setting location", capability: .location) { device, service in
      try service.setLocation(latitude: latitude, longitude: longitude, device: device)
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

  private func bootedSelection() -> Device? {
    guard let device = state.selectedDevice else {
      appendOutput("No device selected", error: true)
      return nil
    }
    if let reason = device.unreadyReason {
      appendOutput(reason, error: true)
      return nil
    }
    return device
  }

  /// Checks the highlighted device can do this before starting any work.
  private func selection(for capability: DeviceCapability) -> Device? {
    guard let device = bootedSelection() else { return nil }
    guard device.supports(capability) else {
      appendOutput(
        SimctlBuddyError.unsupportedAction(capability, kind: device.kind).localizedDescription,
        error: true)
      return nil
    }
    return device
  }

  private func onBootedDevice(
    _ label: String,
    reload: Bool = false,
    capability: DeviceCapability? = nil,
    _ operation: @escaping @Sendable (Device, DeviceService) throws -> String
  ) {
    guard let device = capability.map({ selection(for: $0) }) ?? bootedSelection()
    else { return }
    let service = self.service
    startJob(label) {
      let message = try operation(device, service)
      return reload ? .reload(message) : .message(message)
    }
  }

  // MARK: - Firebase App Distribution

  /// Picks which Firebase app to read builds from.
  ///
  /// Saved apps only: browsing every project would need two more API calls
  /// before anything useful appears on screen, and the app is the part people
  /// keep rather than rediscover.
  private func openFirebaseAppPicker() {
    guard selection(for: .firebaseInstall) != nil else { return }
    guard !state.firebaseApps.isEmpty else {
      appendOutput("No saved Firebase apps yet — add one first", error: true)
      beginPrompt(.firebaseAppID, label: "Firebase app ID")
      return
    }
    state.picker = TUIPicker(
      purpose: .firebaseApp,
      title: "App Distribution \u{00B7} pick an app",
      footnote: "Tab types an app ID instead",
      loadingMessage: "",
      options: state.firebaseApps.map {
        TUIPickerOption(value: $0.appID, label: $0.name, detail: $0.appID)
      },
      isLoading: false
    )
  }

  /// Offers every Firebase app this credential can see, so saving one is a
  /// choice rather than a paste.
  ///
  /// Walking every project costs a call each, so the list arrives in the
  /// background; `Tab` still types an ID by hand for anyone who has one.
  private func openFirebaseAppBrowser() {
    let saved = Set(state.firebaseApps.map(\.appID))
    state.picker = TUIPicker(
      purpose: .firebaseAppToSave,
      title: "Save a Firebase app \u{00B7} pick one",
      footnote: "Tab types an app ID by hand \u{00B7} IDs are in the console under Project settings \u{203A} Your apps",
      loadingMessage: "Reading your Firebase projects",
      options: [],
      isLoading: true
    )
    startJob("Reading Firebase apps") {
      let listings = try FirebaseDistribution().allApps()
      let options = listings.flatMap { listing in
        listing.apps.map { app in
          TUIPickerOption(
            value: app.appID,
            label: app.displayName,
            detail: saved.contains(app.appID)
              ? "\(listing.projectID) \u{00B7} already saved"
              : listing.projectID
          )
        }
      }
      guard !options.isEmpty else {
        let refused = listings.filter { !$0.isReadable }
        return .pickerOptions(
          [],
          message: refused.isEmpty
            ? "No iOS apps in any project you can see"
            : "No readable projects. These need the App Distribution Viewer role: "
              + refused.map(\.projectID).joined(separator: ", "))
      }
      return .pickerOptions(options)
    }
  }

  /// Lists the builds for an app, newest first.
  private func openFirebaseReleasePicker(appID: String) {
    guard let device = selection(for: .firebaseInstall) else { return }
    state.picker = TUIPicker(
      purpose: .firebaseRelease(appID: appID),
      title: "App Distribution \u{00B7} pick a build",
      footnote: "Newest first \u{00B7} installs on \(device.name)",
      loadingMessage: "Reading builds from Firebase",
      options: [],
      isLoading: true
    )
    let store = self.firebaseStore
    startJob("Reading builds") {
      let releases = try FirebaseDistribution(store: store).releases(app: appID, limit: 50)
      guard !releases.isEmpty else {
        return .pickerOptions([], message: "No builds have been uploaded for this app")
      }
      return .pickerOptions(
        releases.map { release in
          var detail = release.createTime.map(Self.relativeDate) ?? release.releaseID
          if let summary = release.summaryLine {
            detail += " \u{00B7} \(summary)"
          }
          return TUIPickerOption(
            value: release.releaseID,
            label: release.versionLabel,
            detail: detail
          )
        })
    }
  }

  /// Downloads a build and installs it, after checking it is signed for this
  /// device. Refusing here beats a signing failure on the phone.
  private func installFirebaseRelease(_ releaseID: String, appID: String) {
    guard let device = selection(for: .firebaseInstall) else { return }
    let store = self.firebaseStore
    let service = self.service
    startJob("Installing from App Distribution") {
      let distribution = FirebaseDistribution(service: service, store: store)
      let report = try distribution.install(releaseID: releaseID, app: appID, on: device)
      var details = report.notes
      if let profile = report.profile, let name = profile.name {
        details.append("Signed with \(name)")
      }
      return .reload(
        "Installed \(report.release.versionLabel) on \(device.name)", details: details)
    }
  }

  /// Says where App Distribution stands and what to do next.
  ///
  /// Deliberately never fails: someone pressing this has usually not set it up
  /// yet, and a red error tells them nothing they can act on. Missing pieces are
  /// reported as the next step instead.
  private func showFirebaseStatus() {
    let savedApps = state.firebaseApps
    startJob("Checking Firebase sign-in") {
      let credentials = FirebaseCredentials()
      let sources = credentials.availableSources()

      guard let token = try? credentials.token() else {
        return .report(
          "Not signed in to Firebase \u{2014} 3 steps to set it up",
          details: [
            "1. Sign in with ONE of these, in a normal terminal:",
            "     gcloud auth login",
            "     firebase login",
            "     simbuddy config set firebase-service-account <key.json>",
            "2. Save an app: the \u{201C}Save Firebase app ID\u{201D} action below.",
            "     It lists every app you can see, so nothing needs pasting.",
            "3. Select a connected device, then press f to pick a build.",
            "",
            sources.isEmpty
              ? "Nothing found on this machine yet."
              : "Found, but not usable: \(sources.joined(separator: ", "))",
          ])
      }

      var details = sources
      if savedApps.isEmpty {
        details.append(
          "No apps saved yet \u{2014} \u{201C}Save Firebase app ID\u{201D} lists every app you can see.")
      } else {
        details.append(
          "\(savedApps.count) app\(savedApps.count == 1 ? "" : "s") saved. "
            + "Select a connected device and press f to install a build.")
      }
      return .report("Signed in through \(token.source.label)", details: details)
    }
  }

  private static func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func appendOutput(_ message: String, error: Bool = false) {
    appendReport(message, details: [], error: error)
  }

  /// Newest entries sit at the top, so detail lines go in before their headline
  /// to keep the block reading top-down.
  private func appendReport(_ message: String, details: [String], error: Bool) {
    for line in details.flatMap(Self.entryLines).reversed() {
      state.output.insert("  \(line)", at: 0)
    }
    // A message can arrive with newlines in it — several errors explain
    // themselves over more than one line. Each becomes its own entry, indented
    // under the headline so the block still reads as one report.
    let lines = Self.entryLines(message)
    for line in lines.dropFirst().reversed() {
      state.output.insert("  \(line)", at: 0)
    }
    state.output.insert("\(error ? "✗" : "✓") \(lines.first ?? message)", at: 0)
    state.output = Array(state.output.prefix(60))
  }

  /// Breaks text into single-line entries.
  ///
  /// Nothing in the activity panel may contain a newline or a tab: the panel is
  /// drawn by positioning the cursor per line, so a stray control character
  /// moves it mid-frame and tears the rest of the layout apart.
  static func entryLines(_ value: String) -> [String] {
    value
      .components(separatedBy: .newlines)
      .map {
        $0.replacingOccurrences(of: "\t", with: "    ")
          .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
      }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

}
