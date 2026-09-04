import Foundation

/// Preferences that outlive a single command. Everything is optional so an
/// absent settings file behaves exactly like the old built-in defaults.
public struct Settings: Codable, Equatable, Sendable {
  public var screenshotDirectory: String?
  public var recordingDirectory: String?
  /// Path to a Google service account key, for reading App Distribution when
  /// the machine has no gcloud or Firebase CLI signed in.
  public var firebaseServiceAccount: String?
  /// Fraction of the window given to the devices panel, or nil for the default.
  public var devicePanelWidth: Double?
  /// Fraction of the window given to the actions panel, or nil for the default.
  public var actionPanelWidth: Double?

  public init(
    screenshotDirectory: String? = nil,
    recordingDirectory: String? = nil,
    firebaseServiceAccount: String? = nil,
    devicePanelWidth: Double? = nil,
    actionPanelWidth: Double? = nil
  ) {
    self.screenshotDirectory = screenshotDirectory
    self.recordingDirectory = recordingDirectory
    self.firebaseServiceAccount = firebaseServiceAccount
    self.devicePanelWidth = devicePanelWidth
    self.actionPanelWidth = actionPanelWidth
  }

  public static let empty = Settings()
}

/// The settings a command can change, named as they appear on the command line.
public enum SettingsKey: String, CaseIterable, Sendable {
  case screenshotDirectory = "screenshot-directory"
  case recordingDirectory = "recording-directory"
  case firebaseServiceAccount = "firebase-service-account"
  case devicePanelWidth = "device-panel-width"
  case actionPanelWidth = "action-panel-width"

  /// True for settings that hold a fraction of the window rather than a path.
  public var isFraction: Bool {
    switch self {
    case .devicePanelWidth, .actionPanelWidth: return true
    default: return false
    }
  }

  public var summary: String {
    switch self {
    case .screenshotDirectory: return "Where `screenshot` writes when no path is given"
    case .recordingDirectory: return "Where `record` writes when no path is given"
    case .firebaseServiceAccount:
      return "Service account key used to read Firebase App Distribution"
    case .devicePanelWidth:
      return "Share of the window given to the devices panel, 0.1 to 0.6"
    case .actionPanelWidth:
      return "Share of the window given to the actions panel, 0.1 to 0.6"
    }
  }
}

extension SettingsStore {
  /// Narrower than this and a panel cannot show a name; wider and the activity
  /// panel has nothing left once both side panels are counted.
  public static let fractionRange: ClosedRange<Double> = 0.1...0.6

  /// Reads a share of the window, written as a fraction or a percentage.
  ///
  /// Both `0.45` and `45%` are accepted, and so is a bare `45`: a share above
  /// one can only have been meant as a percentage.
  public static func fraction(from value: String, key: SettingsKey) throws -> Double {
    var text = value.trimmingCharacters(in: .whitespaces)
    var wasPercent = false
    if text.hasSuffix("%") {
      text.removeLast()
      wasPercent = true
      text = text.trimmingCharacters(in: .whitespaces)
    }
    guard let number = Double(text), number.isFinite else {
      throw SimctlBuddyError.invalidFraction(value: value, key: key.rawValue)
    }
    let fraction = (wasPercent || number > 1) ? number / 100 : number
    guard fractionRange.contains(fraction) else {
      throw SimctlBuddyError.invalidFraction(value: value, key: key.rawValue)
    }
    return fraction
  }

  static func format(_ fraction: Double) -> String {
    String(format: "%.2f", fraction)
  }
}

public struct SettingsStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      self.fileURL = ConfigDirectory.file("settings.json")
    }
  }

  public func load() throws -> Settings {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
    let data = try Data(contentsOf: fileURL)
    guard !data.isEmpty else { return .empty }
    return try JSONDecoder().decode(Settings.self, from: data)
  }

  public func value(for key: SettingsKey) throws -> String? {
    let settings = try load()
    switch key {
    case .screenshotDirectory: return settings.screenshotDirectory
    case .recordingDirectory: return settings.recordingDirectory
    case .firebaseServiceAccount: return settings.firebaseServiceAccount
    case .devicePanelWidth: return settings.devicePanelWidth.map(Self.format)
    case .actionPanelWidth: return settings.actionPanelWidth.map(Self.format)
    }
  }

  /// Stores a directory, creating it when it does not exist yet so the next
  /// screenshot or recording does not fail on a path that looked fine.
  @discardableResult
  public func set(_ key: SettingsKey, to path: String) throws -> String {
    var settings = try load()
    let resolved: String
    switch key {
    case .screenshotDirectory:
      resolved = try Self.prepareDirectory(path)
      settings.screenshotDirectory = resolved
    case .recordingDirectory:
      resolved = try Self.prepareDirectory(path)
      settings.recordingDirectory = resolved
    case .firebaseServiceAccount:
      // A key file, not a folder: it has to exist already, and creating one
      // would be nonsense.
      resolved = Self.absolutePath(path)
      guard FileManager.default.fileExists(atPath: resolved) else {
        throw SimctlBuddyError.missingFile(resolved)
      }
      settings.firebaseServiceAccount = resolved
    case .devicePanelWidth:
      let fraction = try Self.fraction(from: path, key: key)
      settings.devicePanelWidth = fraction
      resolved = Self.format(fraction)
    case .actionPanelWidth:
      let fraction = try Self.fraction(from: path, key: key)
      settings.actionPanelWidth = fraction
      resolved = Self.format(fraction)
    }
    try save(settings)
    return resolved
  }

  public func clear(_ key: SettingsKey) throws {
    var settings = try load()
    switch key {
    case .screenshotDirectory: settings.screenshotDirectory = nil
    case .recordingDirectory: settings.recordingDirectory = nil
    case .firebaseServiceAccount: settings.firebaseServiceAccount = nil
    case .devicePanelWidth: settings.devicePanelWidth = nil
    case .actionPanelWidth: settings.actionPanelWidth = nil
    }
    try save(settings)
  }

  public func save(_ settings: Settings) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(settings)
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }

  /// Expands `~`, makes the path absolute, and creates the directory. Throws if
  /// the path already exists as a file.
  public static func prepareDirectory(_ path: String) throws -> String {
    let absolute = absolutePath(path)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else { throw SimctlBuddyError.notADirectory(absolute) }
      return absolute
    }
    do {
      try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: absolute),
        withIntermediateDirectories: true
      )
    } catch {
      throw SimctlBuddyError.cannotCreateDirectory(absolute, reason: error.localizedDescription)
    }
    return absolute
  }

  public static func absolutePath(_ path: String) -> String {
    let expanded = NSString(string: path).expandingTildeInPath
    let absolute =
      expanded.hasPrefix("/")
      ? expanded
      : NSString(string: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(expanded)
    return NSString(string: absolute).standardizingPath
  }
}

extension Settings {
  /// Where a capture should go: an explicit path wins, then the configured
  /// directory, then the working directory.
  public func destination(
    explicit: String?,
    directory: String?,
    fileName: String
  ) -> String {
    if let explicit, !explicit.isEmpty {
      return SettingsStore.absolutePath(explicit)
    }
    let base = directory ?? FileManager.default.currentDirectoryPath
    return SettingsStore.absolutePath(
      NSString(string: base).appendingPathComponent(fileName)
    )
  }

  public func screenshotDestination(explicit: String? = nil, fileName: String) -> String {
    destination(explicit: explicit, directory: screenshotDirectory, fileName: fileName)
  }

  public func recordingDestination(explicit: String? = nil, fileName: String) -> String {
    destination(explicit: explicit, directory: recordingDirectory, fileName: fileName)
  }
}

/// Timestamped names, so repeated captures never overwrite each other.
public enum CaptureName {
  public static func screenshot(at date: Date = Date()) -> String {
    "simbuddy-\(timestamp(date)).png"
  }

  public static func recording(at date: Date = Date()) -> String {
    "simbuddy-\(timestamp(date)).mov"
  }

  public static func timestamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }
}
