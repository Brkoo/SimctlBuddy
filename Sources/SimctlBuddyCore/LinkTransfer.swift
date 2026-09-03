import Foundation

/// What an import did, named entry by entry so the report can be specific
/// instead of just counting.
public struct ImportSummary: Equatable, Sendable {
  public var added: [String] = []
  public var replaced: [String] = []
  public var skipped: [String] = []
  public var invalid: [String] = []

  public init(
    added: [String] = [],
    replaced: [String] = [],
    skipped: [String] = [],
    invalid: [String] = []
  ) {
    self.added = added
    self.replaced = replaced
    self.skipped = skipped
    self.invalid = invalid
  }

  public var changedCount: Int { added.count + replaced.count }

  public var isEmpty: Bool {
    added.isEmpty && replaced.isEmpty && skipped.isEmpty && invalid.isEmpty
  }

  public var headline: String {
    guard !isEmpty else { return "That file contained no deep links" }
    var parts = [String]()
    if !added.isEmpty { parts.append("\(added.count) added") }
    if !replaced.isEmpty { parts.append("\(replaced.count) replaced") }
    if !skipped.isEmpty { parts.append("\(skipped.count) skipped") }
    if !invalid.isEmpty { parts.append("\(invalid.count) invalid") }
    return parts.joined(separator: ", ")
  }

  /// One line per entry, for the log or for stdout.
  public var details: [String] {
    added.map { "added \($0)" }
      + replaced.map { "replaced \($0)" }
      + skipped.map { "skipped \($0) — a link with that name already exists" }
      + invalid.map { "invalid \($0)" }
  }
}

public enum ImportStrategy: Sendable, Equatable {
  /// Keep what is already saved when the names collide.
  case skipExisting
  /// Overwrite a saved link when the names collide, keep the rest.
  case replaceExisting
  /// Throw away every saved link and use the file as it stands.
  case replaceAll
}

extension LinkStore {
  /// The exported bytes are the same shape as `links.json`, so an export can be
  /// dropped straight into another machine's config directory and an untouched
  /// `links.json` can be imported as-is.
  public func exportData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(try load())
    data.append(0x0A)
    return data
  }

  /// Writes an export and returns the absolute path it landed on.
  @discardableResult
  public func export(to path: String) throws -> String {
    let absolute = SettingsStore.absolutePath(path)
    let data = try exportData()
    try FileManager.default.createDirectory(
      at: URL(fileURLWithPath: absolute).deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: URL(fileURLWithPath: absolute), options: .atomic)
    return absolute
  }

  @discardableResult
  public func importLinks(
    fromFileAt path: String,
    strategy: ImportStrategy = .skipExisting
  ) throws -> ImportSummary {
    let absolute = SettingsStore.absolutePath(path)
    guard FileManager.default.fileExists(atPath: absolute) else {
      throw SimctlBuddyError.missingFile(absolute)
    }
    return try importLinks(from: try Data(contentsOf: absolute.fileURL), strategy: strategy)
  }

  @discardableResult
  public func importLinks(
    from data: Data,
    strategy: ImportStrategy = .skipExisting
  ) throws -> ImportSummary {
    let incoming = try Self.decode(data)
    var existing = strategy == .replaceAll ? [] : try load()
    var summary = ImportSummary()

    for candidate in incoming {
      let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
      let url = candidate.url.trimmingCharacters(in: .whitespacesAndNewlines)
      // Templates are valid links, so check the rendered shape rather than the
      // raw text.
      guard !name.isEmpty, (try? LinkTemplate.parse(url).validate()) != nil else {
        summary.invalid.append(name.isEmpty ? url : "\(name) → \(url)")
        continue
      }

      if let index = existing.firstIndex(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      }) {
        switch strategy {
        case .skipExisting:
          summary.skipped.append(name)
        case .replaceExisting, .replaceAll:
          // replaceAll starts from an empty set, so reaching here means the
          // file itself listed the same name twice; last one wins.
          existing[index] = SavedLink(name: name, url: url, apps: candidate.apps)
          summary.replaced.append(name)
        }
        continue
      }
      existing.append(SavedLink(name: name, url: url, apps: candidate.apps))
      summary.added.append(name)
    }

    if summary.changedCount > 0 || strategy == .replaceAll {
      try save(existing)
    }
    return summary
  }

  /// Accepts a bare array, which is what `links.json` and `export` contain, and
  /// an object with a `links` key, which is what people tend to hand-write.
  private static func decode(_ data: Data) throws -> [SavedLink] {
    let decoder = JSONDecoder()
    if let links = try? decoder.decode([SavedLink].self, from: data) { return links }
    struct Wrapper: Decodable { let links: [SavedLink] }
    if let wrapper = try? decoder.decode(Wrapper.self, from: data) { return wrapper.links }
    do {
      _ = try decoder.decode([SavedLink].self, from: data)
      return []
    } catch {
      throw SimctlBuddyError.invalidImportFile(error.localizedDescription)
    }
  }
}

extension String {
  fileprivate var fileURL: URL { URL(fileURLWithPath: self) }
}
