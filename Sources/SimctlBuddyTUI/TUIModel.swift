import Foundation
import SimctlBuddyCore

public enum TUIFocus: Equatable, Sendable {
  case devices
  case actions
}

public enum TUIActionID: Equatable, Sendable {
  case openDeepLink
  case savedLink(SavedLink)
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
  case installApp
  case launchApp
  case terminateApp
  case clipboard
  case location
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
  public var selectedDeviceIndex = 0
  public var selectedActionIndex = 0
  public var focus = TUIFocus.devices
  public var output: [String] = []
  public var prompt: TUIPrompt?
  public var showingHelp = false

  public init(devices: [SimulatorDevice] = [], links: [SavedLink] = []) {
    self.devices = devices
    self.links = links
  }

  public var selectedDevice: SimulatorDevice? {
    devices.indices.contains(selectedDeviceIndex) ? devices[selectedDeviceIndex] : nil
  }

  public var actions: [TUIActionItem] {
    var result = [
      TUIActionItem(id: .openDeepLink, title: "Open deep link", hint: "o")
    ]
    result += links.map {
      TUIActionItem(id: .savedLink($0), title: "↗ \($0.name)", hint: "saved")
    }
    result += [
      TUIActionItem(id: .boot, title: "Boot / show simulator", hint: "b"),
      TUIActionItem(id: .shutdown, title: "Shut down simulator", hint: "x"),
      TUIActionItem(id: .installApp, title: "Install .app bundle", hint: "i"),
      TUIActionItem(id: .launchApp, title: "Launch app", hint: "L"),
      TUIActionItem(id: .terminateApp, title: "Terminate app", hint: "t"),
      TUIActionItem(id: .screenshot, title: "Take screenshot", hint: "s"),
      TUIActionItem(id: .clipboard, title: "Copy text to simulator", hint: "c"),
      TUIActionItem(id: .location, title: "Set location", hint: "g"),
      TUIActionItem(id: .appearanceDark, title: "Dark appearance", hint: ""),
      TUIActionItem(id: .appearanceLight, title: "Light appearance", hint: ""),
      TUIActionItem(id: .cleanStatusBar, title: "Clean status bar", hint: ""),
      TUIActionItem(id: .clearStatusBar, title: "Clear status override", hint: ""),
      TUIActionItem(id: .refresh, title: "Refresh devices", hint: "r"),
    ]
    return result
  }

  public mutating func moveSelection(by offset: Int) {
    switch focus {
    case .devices:
      guard !devices.isEmpty else { return }
      selectedDeviceIndex = wrappedIndex(selectedDeviceIndex + offset, count: devices.count)
    case .actions:
      guard !actions.isEmpty else { return }
      selectedActionIndex = wrappedIndex(selectedActionIndex + offset, count: actions.count)
    }
  }

  public mutating func toggleFocus() {
    focus = focus == .devices ? .actions : .devices
  }

  public mutating func clampSelections() {
    selectedDeviceIndex = min(max(0, selectedDeviceIndex), max(0, devices.count - 1))
    selectedActionIndex = min(max(0, selectedActionIndex), max(0, actions.count - 1))
  }

  private func wrappedIndex(_ value: Int, count: Int) -> Int {
    (value % count + count) % count
  }
}
