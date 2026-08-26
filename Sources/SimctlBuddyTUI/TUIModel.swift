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
  public var options: [TUIPickerOption]
  public var query = ""
  public var selectedIndex = 0
  public var isLoading: Bool

  public init(
    purpose: TUIPickerPurpose,
    title: String,
    options: [TUIPickerOption] = [],
    isLoading: Bool = true
  ) {
    self.purpose = purpose
    self.title = title
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
  case savedApp(SavedApp)
  case saveApp
  case boot
  case shutdown
  case installApp
  case launchApp
  case terminateApp
  case screenshot
  case clipboard
  case location
  case appearanceDark
  case appearanceLight
  case cleanStatusBar
  case clearStatusBar
  case listApps
  case push
  case privacy(TUIPrivacyAction)
  case privacyReset
  case clipboardPaste
  case locationClear
  case doctor
  case refresh
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

  /// Confirmations show a question instead of a text field.
  public var isConfirmation: Bool {
    switch self {
    case .confirmRemoveSavedLink, .confirmRemoveSavedApp: return true
    default: return false
    }
  }
}

public struct TUIPrompt: Equatable, Sendable {
  public let kind: TUIPromptKind
  public let label: String
  public var value: String

  public init(kind: TUIPromptKind, label: String, value: String = "") {
    self.kind = kind
    self.label = label
    self.value = value
  }
}

public struct TUIState: Sendable {
  public var devices: [SimulatorDevice]
  public var links: [SavedLink]
  public var apps: [SavedApp] = []
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

  public var actions: [TUIActionItem] {
    var result = [
      TUIActionItem(id: .openDeepLink, title: "Open deep link", hint: "o"),
      TUIActionItem(id: .addSavedLink, title: "Add saved deep link", hint: "a"),
    ]
    result += links.map {
      TUIActionItem(id: .savedLink($0), title: "↗ \($0.name)", hint: "↵/e/d")
    }
    result += apps.map {
      TUIActionItem(id: .savedApp($0), title: "▶ \($0.name)", hint: "↵/e/d")
    }
    result.append(TUIActionItem(id: .saveApp, title: "Save app bundle ID", hint: ""))
    result += [
      TUIActionItem(id: .boot, title: "Boot / show simulator", hint: "b"),
      TUIActionItem(id: .shutdown, title: "Shut down simulator", hint: "x"),
      TUIActionItem(id: .installApp, title: "Install .app bundle", hint: "i"),
      TUIActionItem(id: .launchApp, title: "Launch app", hint: "L"),
      TUIActionItem(id: .terminateApp, title: "Terminate app", hint: "t"),
      TUIActionItem(id: .listApps, title: "List installed apps", hint: ""),
      TUIActionItem(id: .push, title: "Send push notification", hint: "p"),
      TUIActionItem(id: .privacy(.grant), title: "Grant privacy permission", hint: ""),
      TUIActionItem(id: .privacy(.revoke), title: "Revoke privacy permission", hint: ""),
      TUIActionItem(id: .privacyReset, title: "Reset privacy permissions", hint: ""),
      TUIActionItem(id: .screenshot, title: "Take screenshot", hint: "s"),
      TUIActionItem(id: .clipboard, title: "Copy text to simulator", hint: "c"),
      TUIActionItem(id: .clipboardPaste, title: "Read simulator clipboard", hint: "v"),
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
