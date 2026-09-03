import Foundation

public struct SavedLink: Codable, Equatable, Sendable {
  public let name: String
  public let url: String
  /// Bundle identifiers this link belongs to. Empty or absent means any app.
  public let apps: [String]?

  public init(name: String, url: String, apps: [String]? = nil) {
    self.name = name
    self.url = url
    self.apps = (apps?.isEmpty ?? true) ? nil : apps
  }

  public var template: LinkTemplate {
    LinkTemplate.parse(url)
  }

  /// True when this link is offered for the given app.
  public func appliesTo(bundleIdentifier: String) -> Bool {
    guard let apps, !apps.isEmpty else { return true }
    return apps.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
  }

  public var isRestricted: Bool {
    !(apps?.isEmpty ?? true)
  }
}

public struct LinkStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      self.fileURL = ConfigDirectory.file("links.json")
    }
  }

  public func load() throws -> [SavedLink] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([SavedLink].self, from: data)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func add(
    name: String,
    url: String,
    apps: [String]? = nil,
    force: Bool
  ) throws {
    // A template is checked by rendering it with stand-in values, so
    // "$scheme://x" is accepted while a genuine typo still is not.
    try LinkTemplate.parse(url).validate()
    var links = try load()
    let entry = SavedLink(name: name, url: url, apps: apps)
    if let index = links.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    {
      guard force else { throw SimctlBuddyError.duplicateLink(name) }
      links[index] = entry
    } else {
      links.append(entry)
    }
    try save(links)
  }

  public func remove(name: String) throws {
    var links = try load()
    guard
      let index = links.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else {
      throw SimctlBuddyError.linkNotFound(name)
    }
    links.remove(at: index)
    try save(links)
  }

  public func link(named name: String) throws -> SavedLink {
    guard
      let link = try load().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else {
      throw SimctlBuddyError.linkNotFound(name)
    }
    return link
  }

  /// Internal rather than private so import can write a merged set.
  func save(_ links: [SavedLink]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(links.sorted { $0.name < $1.name })
    data.append(0x0A)
    try data.write(to: fileURL, options: .atomic)
  }
}
