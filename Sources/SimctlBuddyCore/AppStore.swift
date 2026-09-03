import Foundation

public struct SavedApp: Codable, Equatable, Sendable {
  public let name: String
  public let bundleIdentifier: String
  /// The app's URL scheme, when it has one. Deep links written with `$scheme`
  /// resolve it from here, so one link definition covers every market's app.
  public let scheme: String?

  public init(name: String, bundleIdentifier: String, scheme: String? = nil) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
    self.scheme = scheme
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
      self.fileURL = ConfigDirectory.file("apps.json")
    }
  }

  public func load() throws -> [SavedApp] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([SavedApp].self, from: data)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func add(
    name: String,
    bundleIdentifier: String,
    scheme: String? = nil,
    force: Bool
  ) throws {
    let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Self.isValidBundleIdentifier(identifier) else {
      throw SimctlBuddyError.invalidBundleIdentifier(bundleIdentifier)
    }
    let trimmedScheme = scheme?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedScheme = (trimmedScheme?.isEmpty ?? true) ? nil : trimmedScheme
    if let resolvedScheme, !LinkTemplate.isValidScheme(resolvedScheme) {
      throw SimctlBuddyError.invalidScheme(resolvedScheme)
    }

    var apps = try load()
    let entry = SavedApp(name: name, bundleIdentifier: identifier, scheme: resolvedScheme)
    if let index = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
      guard force else { throw SimctlBuddyError.duplicateApp(name) }
      apps[index] = entry
    } else {
      apps.append(entry)
    }
    try save(apps)
  }

  /// Apps that can supply a `$scheme`, in display order.
  public func appsWithSchemes() throws -> [SavedApp] {
    try load().filter { $0.scheme != nil }
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
