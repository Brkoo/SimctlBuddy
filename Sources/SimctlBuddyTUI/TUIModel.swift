import Foundation
import SimctlBuddyCore

public enum TUIFocus: Equatable, Sendable {
  case devices
  case actions
}

/// Screen modes mirror Lazygit: each step gives the focused panel more room.
public enum TUIScreenMode: Equatable, CaseIterable, Sendable {
  case normal
  case half
  case full
}

public enum TUIPrivacyAction: String, Equatable, Sendable {
  case grant
  case revoke
}

/// What a chosen bundle identifier should be used for.
public enum TUIPickerPurpose: Equatable, Sendable {
  case launchApp
  case terminateApp
  case pushBundle
  case privacyBundle(action: TUIPrivacyAction, service: String)
  case privacyResetBundle
  case saveApp
  /// The chosen value is a path to a .app bundle, not a bundle identifier.
  case installPath
  case savePath
  /// Which app a `$scheme` link should be opened on.
  case linkApp
  /// Which Firebase app to read builds from.
  case firebaseApp
  /// Which Firebase app to remember under a name. The value is an app ID.
  case firebaseAppToSave
  /// Which build to install. The value is a release ID.
  case firebaseRelease(appID: String)
}

public struct TUIPickerOption: Equatable, Sendable {
  public let value: String
  public let label: String
  public let detail: String

  public init(value: String, label: String, detail: String) {
    self.value = value
    self.label = label
    self.detail = detail
  }
}

/// A searchable list of bundle identifiers, so app actions never require typing
/// an identifier from memory.
public struct TUIPicker: Equatable, Sendable {
  public let purpose: TUIPickerPurpose
  public let title: String
  /// What Tab does here, and what the list is ordered by.
  public let footnote: String
  public let loadingMessage: String
  public var options: [TUIPickerOption]
  public var query = ""
  public var selectedIndex = 0
  public var isLoading: Bool

  public init(
    purpose: TUIPickerPurpose,
    title: String,
    footnote: String = "Saved apps are listed first",
    loadingMessage: String = "Reading installed apps",
    options: [TUIPickerOption] = [],
    isLoading: Bool = true
  ) {
    self.purpose = purpose
    self.title = title
    self.footnote = footnote
    self.loadingMessage = loadingMessage
    self.options = options
    self.isLoading = isLoading
  }

  public var visibleOptions: [TUIPickerOption] {
    guard !query.isEmpty else { return options }
    let needle = query.lowercased()
    return options.filter {
      $0.label.lowercased().contains(needle) || $0.value.lowercased().contains(needle)
    }
  }

  public var selectedOption: TUIPickerOption? {
    let items = visibleOptions
    return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
  }

  public mutating func moveSelection(by offset: Int) {
    let count = visibleOptions.count
    guard count > 0 else { return }
    selectedIndex = ((selectedIndex + offset) % count + count) % count
  }
}

public enum TUIActionID: Equatable, Sendable {
  case openDeepLink
  case addSavedLink
  case savedLink(SavedLink)
  case exportLinks
  case importLinks
  case savedApp(SavedApp)
  case saveApp
  case savedPath(SavedPath)
  case savePath
  case savedFirebaseApp(SavedFirebaseApp)
  case saveFirebaseApp
  case firebaseInstall
  case firebaseStatus
  case boot
  case shutdown
  case installApp
  case launchApp
  case terminateApp
  case screenshot
  case startRecording
  case stopRecording
  case screenshotDirectory
  case recordingDirectory
  case clipboard
  case location
  case appearanceDark
  case appearanceLight
  case cleanStatusBar
  case clearStatusBar
  case listApps
  case listRunningApps
  case push
  case privacy(TUIPrivacyAction)
  case privacyReset
  case clipboardPaste
  case locationClear
  case doctor
  case refresh
}

extension TUIActionID {
  /// The capability this action needs, or nil when it is not device work.
  public var capability: DeviceCapability? {
    switch self {
    case .openDeepLink, .addSavedLink, .savedLink: return .openURL
    case .exportLinks, .importLinks: return nil
    case .savedApp: return .launch
    case .saveApp: return .listApps
    case .savedPath, .savePath, .installApp: return .install
    case .savedFirebaseApp, .firebaseInstall: return .firebaseInstall
    case .saveFirebaseApp, .firebaseStatus: return nil
    case .boot: return .boot
    case .shutdown: return .shutdown
    case .launchApp: return .launch
    case .terminateApp: return .terminate
    case .listApps: return .listApps
    case .listRunningApps: return .runningApps
    case .push: return .push
    case .privacy, .privacyReset: return .privacy
    case .screenshot: return .screenshot
    case .startRecording, .stopRecording: return .record
    case .screenshotDirectory, .recordingDirectory: return nil
    case .clipboard, .clipboardPaste: return .clipboard
    case .location, .locationClear: return .location
    case .appearanceDark, .appearanceLight: return .appearance
    case .cleanStatusBar, .clearStatusBar: return .statusBar
    case .doctor, .refresh: return nil
    }
  }
}

public struct TUIActionItem: Equatable, Sendable {
  public let id: TUIActionID
  public let title: String
  public let hint: String

  public init(id: TUIActionID, title: String, hint: String) {
    self.id = id
    self.title = title
    self.hint = hint
  }
}

public enum TUIPromptKind: Equatable, Sendable {
  case deepLink
  case savedLinkName
  case savedLinkURL(name: String)
  case editSavedLinkURL(name: String)
  case installApp
  case launchApp
  case terminateApp
  case clipboard
  case location
  case pushBundle
  case pushPayload(bundleIdentifier: String)
  case privacyService(action: TUIPrivacyAction)
  case privacyBundle(action: TUIPrivacyAction, service: String)
  case privacyResetBundle
  case confirmRemoveSavedLink(name: String)
  case savedAppName(bundleIdentifier: String)
  case editSavedAppBundle(name: String)
  case confirmRemoveSavedApp(name: String)
  case savedPathValue(name: String)
  case savedPathName(path: String)
  case editSavedPath(name: String)
  case confirmRemoveSavedPath(name: String)
  case firebaseAppID
  case firebaseAppName(appID: String)
  case confirmRemoveFirebaseApp(name: String)
  case screenshotDirectory
  case recordingDirectory
  case exportLinks
  case importLinks
  case savedAppScheme(name: String, bundleIdentifier: String)
  case linkParameter(link: String, parameter: String)

  /// Confirmations show a question instead of a text field.
  public var isConfirmation: Bool {
    switch self {
    case .confirmRemoveSavedLink, .confirmRemoveSavedApp, .confirmRemoveSavedPath,
      .confirmRemoveFirebaseApp:
      return true
    default: return false
    }
  }

  /// Non-nil for fields that hold a path, which is what enables Tab completion
  /// and decides which entries it offers.
  public var pathFilter: PathFilter? {
    switch self {
    case .installApp, .savedPathValue, .editSavedPath:
      return .appBundles
    case .pushPayload:
      return .files(extensions: ["apns", "json"])
    case .exportLinks, .importLinks:
      return .files(extensions: ["json"])
    case .screenshotDirectory, .recordingDirectory:
      return .directories
    default:
      return nil
    }
  }
}

/// Enough of a half-filled deep link to draw it above the field.
///
/// Carried on the prompt rather than rendered once, so the preview can follow
/// what is being typed instead of showing a stale link.
public struct LinkPromptContext: Equatable, Sendable {
  public let template: LinkTemplate
  public let scheme: String?
  public let values: [String: String]
  public let parameter: String
  /// Which of the link's parameters this is, for "2 of 3".
  public let position: Int
  public let total: Int

  public init(
    template: LinkTemplate,
    scheme: String?,
    values: [String: String],
    parameter: String,
    position: Int,
    total: Int
  ) {
    self.template = template
    self.scheme = scheme
    self.values = values
    self.parameter = parameter
    self.position = position
    self.total = total
  }

  public func preview(currentValue: String) -> [LinkPreviewPart] {
    template.preview(
      scheme: scheme, values: values, current: parameter, currentValue: currentValue)
  }
}

public struct TUIPrompt: Equatable, Sendable {
  public let kind: TUIPromptKind
  public let label: String
  public var value: String
  /// What the last Tab press found, shown under the field. Cleared as soon as
  /// typing resumes, so it never describes stale text.
  public var candidates: [String] = []
  public var note: String?
  /// Set while filling in a deep link's parameters, so the field can show where
  /// the value lands.
  public var linkContext: LinkPromptContext?

  public init(
    kind: TUIPromptKind,
    label: String,
    value: String = "",
    linkContext: LinkPromptContext? = nil
  ) {
    self.kind = kind
    self.label = label
    self.value = value
    self.linkContext = linkContext
  }

  public var supportsCompletion: Bool { kind.pathFilter != nil }

  public mutating func clearCompletion() {
    candidates = []
    note = nil
  }

  /// Applies one Tab press. Returns false when nothing matched, so the caller
  /// can say so instead of leaving the field looking unresponsive.
  @discardableResult
  public mutating func complete(using completer: PathCompleter) -> Bool {
    guard let filter = kind.pathFilter else { return false }
    let result = completer.complete(value, filter: filter)
    value = result.value
    if result.isUnique {
      candidates = []
      note = nil
      return true
    }
    guard !result.candidates.isEmpty else {
      candidates = []
      note = "No match"
      return false
    }
    candidates = result.candidates
    note = "\(result.candidates.count) matches"
    return true
  }
}

/// A deep link being opened, part-way through collecting what it needs.
///
/// A template link asks for its app first, then for each parameter, so the run
/// has to survive several prompts.
public struct PendingLink: Equatable, Sendable {
  /// The saved link's name, or empty for one typed in by hand.
  public let linkName: String
  public let template: LinkTemplate
  public var app: SavedApp?
  public var values: [String: String]
  public var remaining: [LinkParameter]

  public init(
    linkName: String,
    template: LinkTemplate,
    app: SavedApp? = nil,
    values: [String: String] = [:],
    remaining: [LinkParameter] = []
  ) {
    self.linkName = linkName
    self.template = template
    self.app = app
    self.values = values
    self.remaining = remaining
  }

  /// The key remembered values are filed under.
  public var memoryKey: String {
    linkName.isEmpty ? LinkValueStore.adHocKey : linkName
  }

  public var title: String {
    linkName.isEmpty ? "Open deep link" : linkName
  }
}

public struct TUIState: Sendable {
  public var devices: [SimulatorDevice]
  public var links: [SavedLink]
  public var apps: [SavedApp] = []
  public var paths: [SavedPath] = []
  public var recentPaths: [String] = []
  public var firebaseApps: [SavedFirebaseApp] = []
  public var settings = Settings.empty
  public var recording: Recorder.Session?
  public var pendingLink: PendingLink?
  public var installedApps: [String] = []
  public var picker: TUIPicker?
  public var selectedDeviceIndex = 0
  public var selectedActionIndex = 0
  public var focus = TUIFocus.devices
  public var output: [String] = []
  public var prompt: TUIPrompt?
  public var showingHelp = false
  public var screenMode = TUIScreenMode.normal
  public var deviceFilter = ""
  public var actionFilter = ""
  public var filtering = false
  public var busy: String?
  public var spinnerFrame = 0

  public init(devices: [SimulatorDevice] = [], links: [SavedLink] = []) {
    self.devices = devices
    self.links = links
  }

  public var selectedDevice: SimulatorDevice? {
    let items = visibleDevices
    return items.indices.contains(selectedDeviceIndex) ? items[selectedDeviceIndex] : nil
  }

  public var selectedAction: TUIActionItem? {
    let items = visibleActions
    return items.indices.contains(selectedActionIndex) ? items[selectedActionIndex] : nil
  }

  /// Devices matching the current filter. Selection indexes into this list.
  public var visibleDevices: [SimulatorDevice] {
    guard !deviceFilter.isEmpty else { return devices }
    let needle = deviceFilter.lowercased()
    return devices.filter {
      $0.name.lowercased().contains(needle) || $0.runtimeName.lowercased().contains(needle)
    }
  }

  /// Actions matching the current filter. Saved links also match on their URL.
  public var visibleActions: [TUIActionItem] {
    guard !actionFilter.isEmpty else { return actions }
    let needle = actionFilter.lowercased()
    return actions.filter { item in
      if item.title.lowercased().contains(needle) { return true }
      if case .savedLink(let link) = item.id {
        return link.url.lowercased().contains(needle)
      }
      if case .savedApp(let app) = item.id {
        return app.bundleIdentifier.lowercased().contains(needle)
      }
      if case .savedPath(let saved) = item.id {
        return saved.path.lowercased().contains(needle)
      }
      if case .savedFirebaseApp(let app) = item.id {
        return app.appID.lowercased().contains(needle)
      }
      return false
    }
  }

  /// The filter belonging to the focused panel.
  public var activeFilter: String {
    get { focus == .devices ? deviceFilter : actionFilter }
    set {
      switch focus {
      case .devices: deviceFilter = newValue
      case .actions: actionFilter = newValue
      }
    }
  }

  public var isRecording: Bool { recording != nil }

  /// What the highlighted device can do. Actions it cannot are left out rather
  /// than offered and refused.
  public var availableCapabilities: Set<DeviceCapability> {
    selectedDevice?.capabilities ?? DeviceKind.simulator.capabilities
  }

  public var actions: [TUIActionItem] {
    let allowed = availableCapabilities
    return allActions.filter { item in
      guard let capability = item.id.capability else { return true }
      return allowed.contains(capability)
    }
  }

  private var allActions: [TUIActionItem] {
    // Booting comes first because nothing else works until the device is ready.
    // A physical device has no boot state, so this section drops out entirely
    // there and the list starts at LINKS instead.
    var result = [
      TUIActionItem(id: .boot, title: "Boot / show simulator", hint: "b"),
      TUIActionItem(id: .shutdown, title: "Shut down simulator", hint: "x"),
    ]
    result += [
      TUIActionItem(id: .openDeepLink, title: "Open deep link", hint: "o"),
      TUIActionItem(id: .addSavedLink, title: "Add saved deep link", hint: "a"),
    ]
    result += links.map {
      TUIActionItem(id: .savedLink($0), title: "↗ \($0.name)", hint: "↵/e/d")
    }
    result += [
      TUIActionItem(id: .exportLinks, title: "Export deep links", hint: ""),
      TUIActionItem(id: .importLinks, title: "Import deep links", hint: ""),
    ]
    result += apps.map {
      TUIActionItem(id: .savedApp($0), title: "▶ \($0.name)", hint: "↵/e/d")
    }
    result.append(TUIActionItem(id: .saveApp, title: "Save app bundle ID", hint: ""))
    result += paths.map {
      TUIActionItem(id: .savedPath($0), title: "⤓ \($0.name)", hint: "↵/e/d")
    }
    result.append(TUIActionItem(id: .savePath, title: "Save .app path", hint: ""))
    result += firebaseApps.map {
      TUIActionItem(id: .savedFirebaseApp($0), title: "\u{2601} \($0.name)", hint: "↵/d")
    }
    result += [
      TUIActionItem(id: .firebaseInstall, title: "Install from App Distribution", hint: "f"),
      TUIActionItem(id: .saveFirebaseApp, title: "Save Firebase app ID", hint: ""),
      TUIActionItem(id: .firebaseStatus, title: "Firebase setup \u{00B7} sign-in and steps", hint: ""),
    ]
    result += [
      TUIActionItem(id: .installApp, title: "Install .app bundle", hint: "i"),
      TUIActionItem(id: .launchApp, title: "Launch app", hint: "L"),
      TUIActionItem(id: .terminateApp, title: "Terminate app", hint: "t"),
      TUIActionItem(id: .listApps, title: "List installed apps", hint: ""),
      TUIActionItem(id: .listRunningApps, title: "List running apps", hint: ""),
      TUIActionItem(id: .push, title: "Send push notification", hint: "p"),
      TUIActionItem(id: .privacy(.grant), title: "Grant privacy permission", hint: ""),
      TUIActionItem(id: .privacy(.revoke), title: "Revoke privacy permission", hint: ""),
      TUIActionItem(id: .privacyReset, title: "Reset privacy permissions", hint: ""),
      TUIActionItem(id: .screenshot, title: "Take screenshot", hint: "s"),
    ]
    // One row that flips, so the recording state is impossible to misread.
    if isRecording {
      result.append(TUIActionItem(id: .stopRecording, title: "Stop recording", hint: "R"))
    } else {
      result.append(TUIActionItem(id: .startRecording, title: "Start recording", hint: "R"))
    }
    result += [
      TUIActionItem(id: .screenshotDirectory, title: "Set screenshot folder", hint: ""),
      TUIActionItem(id: .recordingDirectory, title: "Set recording folder", hint: ""),
      TUIActionItem(id: .clipboard, title: "Copy text to clipboard", hint: "c"),
      TUIActionItem(id: .clipboardPaste, title: "Read the clipboard", hint: "v"),
      TUIActionItem(id: .location, title: "Set location", hint: "g"),
      TUIActionItem(id: .locationClear, title: "Clear location override", hint: ""),
      TUIActionItem(id: .appearanceDark, title: "Dark appearance", hint: ""),
      TUIActionItem(id: .appearanceLight, title: "Light appearance", hint: ""),
      TUIActionItem(id: .cleanStatusBar, title: "Clean status bar", hint: ""),
      TUIActionItem(id: .clearStatusBar, title: "Clear status override", hint: ""),
      TUIActionItem(id: .doctor, title: "Run diagnostics", hint: ""),
      TUIActionItem(id: .refresh, title: "Refresh devices", hint: "r"),
    ]
    return result
  }

  public mutating func moveSelection(by offset: Int) {
    switch focus {
    case .devices:
      let count = visibleDevices.count
      guard count > 0 else { return }
      selectedDeviceIndex = wrappedIndex(selectedDeviceIndex + offset, count: count)
    case .actions:
      let count = visibleActions.count
      guard count > 0 else { return }
      selectedActionIndex = wrappedIndex(selectedActionIndex + offset, count: count)
    }
  }

  /// A new query invalidates the highlighted row, so start from the top again.
  public mutating func resetFocusedSelection() {
    switch focus {
    case .devices: selectedDeviceIndex = 0
    case .actions: selectedActionIndex = 0
    }
  }

  public mutating func clearActiveFilter() {
    activeFilter = ""
    resetFocusedSelection()
  }

  public mutating func growFocusedPanel() {
    screenMode = TUIScreenMode.allCases.next(after: screenMode)
  }

  public mutating func shrinkFocusedPanel() {
    screenMode = TUIScreenMode.allCases.previous(before: screenMode)
  }

  public mutating func toggleFocus() {
    focus = focus == .devices ? .actions : .devices
  }

  public mutating func clampSelections() {
    selectedDeviceIndex = min(max(0, selectedDeviceIndex), max(0, visibleDevices.count - 1))
    selectedActionIndex = min(max(0, selectedActionIndex), max(0, visibleActions.count - 1))
  }

  private func wrappedIndex(_ value: Int, count: Int) -> Int {
    (value % count + count) % count
  }
}

extension Array where Element: Equatable {
  fileprivate func next(after element: Element) -> Element {
    guard let index = firstIndex(of: element) else { return self[0] }
    return self[Swift.min(index + 1, count - 1)]
  }

  fileprivate func previous(before element: Element) -> Element {
    guard let index = firstIndex(of: element) else { return self[0] }
    return self[Swift.max(index - 1, 0)]
  }
}
