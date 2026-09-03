import Foundation

/// Preferences that outlive a single command. Everything is optional so an
/// absent settings file behaves exactly like the old built-in defaults.
public struct Settings: Codable, Equatable, Sendable {
  public var screenshotDirectory: String?
  public var recordingDirectory: String?

  public init(screenshotDirectory: String? = nil, recordingDirectory: String? = nil) {
    self.screenshotDirectory = screenshotDirectory
    self.recordingDirectory = recordingDirectory
  }

  public static let empty = Settings()
}

/// The settings a command can change, named as they appear on the command line.
public enum SettingsKey: String, CaseIterable, Sendable {
  case screenshotDirectory = "screenshot-directory"
  case recordingDirectory = "recording-directory"

  public var summary: String {
    switch self {
    case .screenshotDirectory: return "Where `screenshot` writes when no path is given"
    case .recordingDirectory: return "Where `record` writes when no path is given"
    }
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
    }
  }

  /// Stores a directory, creating it when it does not exist yet so the next
  /// screenshot or recording does not fail on a path that looked fine.
  @discardableResult
  public func set(_ key: SettingsKey, to path: String) throws -> String {
    let resolved = try Self.prepareDirectory(path)
    var settings = try load()
    switch key {
    case .screenshotDirectory: settings.screenshotDirectory = resolved
    case .recordingDirectory: settings.recordingDirectory = resolved
    }
    try save(settings)
    return resolved
  }

  public func clear(_ key: SettingsKey) throws {
    var settings = try load()
    switch key {
    case .screenshotDirectory: settings.screenshotDirectory = nil
    case .recordingDirectory: settings.recordingDirectory = nil
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
