import Foundation

public struct SavedApp: Codable, Equatable, Sendable {
  public let name: String
  public let bundleIdentifier: String

  public init(name: String, bundleIdentifier: String) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
  }
}

/// Remembers app bundle identifiers under friendly names, the same way
/// `LinkStore` remembers deep links.
public struct AppStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config", isDirectory: true)
        .appendingPathComponent("simbuddy", isDirectory: true)
      self.fileURL = base.appendingPathComponent("apps.json")
    }
  }

  public func load() throws -> [SavedApp] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([SavedApp].self, from: data)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func add(name: String, bundleIdentifier: String, force: Bool) throws {
    let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isValidBundleIdentifier(identifier) else {
      throw SimctlBuddyError.invalidBundleIdentifier(bundleIdentifier)
    }
    var apps = try load()
    if let index = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      guard force else { throw SimctlBuddyError.duplicateApp(name) }
      apps[index] = SavedApp(name: name, bundleIdentifier: identifier)
    } else {
      apps.append(SavedApp(name: name, bundleIdentifier: identifier))
    }
    try save(apps)
  }

  public func remove(name: String) throws {
    var apps = try load()
    guard
      let index = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else {
      throw SimctlBuddyError.appNotFound(name)
    }
    apps.remove(at: index)
    try save(apps)
  }

  public func app(named name: String) throws -> SavedApp {
    guard
      let app = try load().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else {
      throw SimctlBuddyError.appNotFound(name)
    }
    return app
  }

  /// Reverse-DNS style identifiers only: at least two dot-separated segments of
  /// letters, digits, and hyphens.
  public static func isValidBundleIdentifier(_ value: String) -> Bool {
    let segments = value.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count >= 2 else { return false }
    return segments.allSatisfy { segment in
      !segment.isEmpty
        && segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
  }

  private func save(_ apps: [SavedApp]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(apps.sorted { $0.name < $1.name })
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }
}
