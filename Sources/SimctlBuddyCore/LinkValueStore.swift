import Foundation

/// What was last used for a link: the value of each parameter, and the app it
/// was opened on. Parameters start from the last value rather than from the
/// template's default, because the value you used a minute ago is usually the
/// one you want again.
public struct LinkMemory: Codable, Equatable, Sendable {
  public var values: [String: String]
  public var app: String?

  public init(values: [String: String] = [:], app: String? = nil) {
    self.values = values
    self.app = app
  }
}

public struct LinkValueStore: Sendable {
  /// Links opened without being saved share one entry.
  public static let adHocKey = "(ad hoc)"

  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      self.fileURL = ConfigDirectory.file("link-values.json")
    }
  }

  public func load() throws -> [String: LinkMemory] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
    let data = try Data(contentsOf: fileURL)
    guard !data.isEmpty else { return [:] }
    return try JSONDecoder().decode([String: LinkMemory].self, from: data)
  }

  public func memory(for link: String) -> LinkMemory {
    (try? load())?[link] ?? LinkMemory()
  }

  /// The value to put in the prompt: what was used last, then the template's
  /// default, then nothing.
  public func startingValue(for parameter: LinkParameter, link: String) -> String {
    memory(for: link).values[parameter.name] ?? parameter.defaultValue ?? ""
  }

  public func remember(values: [String: String], app: String?, for link: String) throws {
    var all = (try? load()) ?? [:]
    var entry = all[link] ?? LinkMemory()
    for (key, value) in values { entry.values[key] = value }
    if let app { entry.app = app }
    all[link] = entry
    try save(all)
  }

  public func forget(_ link: String) throws {
    var all = (try? load()) ?? [:]
    all.removeValue(forKey: link)
    try save(all)
  }

  private func save(_ all: [String: LinkMemory]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(all)
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }
}
