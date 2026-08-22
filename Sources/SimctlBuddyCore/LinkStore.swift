import Foundation

public struct SavedLink: Codable, Equatable, Sendable {
  public let name: String
  public let url: String

  public init(name: String, url: String) {
    self.name = name
    self.url = url
  }
}

public struct LinkStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config", isDirectory: true)
        .appendingPathComponent("simbuddy", isDirectory: true)
      self.fileURL = base.appendingPathComponent("links.json")
    }
  }

  public func load() throws -> [SavedLink] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([SavedLink].self, from: data)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func add(name: String, url: String, force: Bool) throws {
    guard SimctlClient.isValidDeepLink(url) else { throw SimctlBuddyError.invalidURL(url) }
    var links = try load()
    if let index = links.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    {
      guard force else { throw SimctlBuddyError.duplicateLink(name) }
      links[index] = SavedLink(name: name, url: url)
    } else {
      links.append(SavedLink(name: name, url: url))
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

  private func save(_ links: [SavedLink]) throws {
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
