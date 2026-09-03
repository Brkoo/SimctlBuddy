import Foundation

public struct SavedPath: Codable, Equatable, Sendable {
  public let name: String
  public let path: String

  public init(name: String, path: String) {
    self.name = name
    self.path = path
  }

  /// True when the bundle is on disk right now. A saved path is still worth
  /// keeping when it is not — build directories come and go.
  public var exists: Bool {
    FileManager.default.fileExists(atPath: path)
  }
}

/// Named `.app` bundles plus the ones most recently installed, so installing
/// never means retyping a path out of a build directory.
public struct PathBook: Codable, Equatable, Sendable {
  public var saved: [SavedPath]
  public var recent: [String]

  public init(saved: [SavedPath] = [], recent: [String] = []) {
    self.saved = saved
    self.recent = recent
  }
}

public struct PathStore: Sendable {
  /// Enough to be useful without turning the picker into a history dump.
  public static let recentLimit = 10

  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      self.fileURL = ConfigDirectory.file("paths.json")
    }
  }

  public func load() throws -> PathBook {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return PathBook() }
    let data = try Data(contentsOf: fileURL)
    guard !data.isEmpty else { return PathBook() }
    var book = try JSONDecoder().decode(PathBook.self, from: data)
    book.saved.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return book
  }

  public func saved() throws -> [SavedPath] {
    try load().saved
  }

  public func recents() throws -> [String] {
    try load().recent
  }

  public func add(name: String, path: String, force: Bool) throws {
    let resolved = try Self.validate(path)
    var book = try load()
    if let index = book.saved.firstIndex(where: {
      $0.name.caseInsensitiveCompare(name) == .orderedSame
    }) {
      guard force else { throw SimctlBuddyError.duplicatePath(name) }
      book.saved[index] = SavedPath(name: name, path: resolved)
    } else {
      book.saved.append(SavedPath(name: name, path: resolved))
    }
    try save(book)
  }

  public func remove(name: String) throws {
    var book = try load()
    guard
      let index = book.saved.firstIndex(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else { throw SimctlBuddyError.pathNotFound(name) }
    book.saved.remove(at: index)
    try save(book)
  }

  public func path(named name: String) throws -> SavedPath {
    guard
      let match = try load().saved.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else { throw SimctlBuddyError.pathNotFound(name) }
    return match
  }

  /// Records a successful install. Most recent first, no duplicates.
  public func recordRecent(_ path: String) throws {
    let absolute = SettingsStore.absolutePath(path)
    var book = try load()
    book.recent.removeAll { $0 == absolute }
    book.recent.insert(absolute, at: 0)
    book.recent = Array(book.recent.prefix(Self.recentLimit))
    try save(book)
  }

  public func clearRecents() throws {
    var book = try load()
    book.recent = []
    try save(book)
  }

  /// A path worth saving points at a `.app` bundle. Whether it exists is not
  /// checked here: a path can be saved before the first build produces it.
  public static func validate(_ path: String) throws -> String {
    let absolute = SettingsStore.absolutePath(path)
    let trimmed = absolute.hasSuffix("/") ? String(absolute.dropLast()) : absolute
    guard trimmed.lowercased().hasSuffix(".app") else {
      throw SimctlBuddyError.notAnAppBundlePath(absolute)
    }
    return trimmed
  }

  private func save(_ book: PathBook) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    var sorted = book
    sorted.saved.sort { $0.name < $1.name }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(sorted)
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }
}
