import Foundation

/// A Firebase app saved under a friendly name, so installing a build never
/// means pasting `1:123456789:ios:abcdef` out of the console again.
public struct SavedFirebaseApp: Codable, Equatable, Sendable {
  public let name: String
  public let appID: String

  public init(name: String, appID: String) {
    self.name = name
    self.appID = appID
  }

  public var projectNumber: String? {
    FirebaseApp(appID: appID, displayName: name).projectNumber
  }
}

public struct FirebaseStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? ConfigDirectory.file("firebase.json")
  }

  public func load() throws -> [SavedFirebaseApp] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    guard !data.isEmpty else { return [] }
    return try JSONDecoder().decode([SavedFirebaseApp].self, from: data)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func add(name: String, appID: String, force: Bool) throws {
    let identifier = try FirebaseApp.validate(appID)
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw SimctlBuddyError.invalidFirebaseAppID("A saved app needs a name.")
    }
    var apps = try load()
    if let index = apps.firstIndex(where: {
      $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
    }) {
      guard force else { throw SimctlBuddyError.duplicateFirebaseApp(trimmedName) }
      apps[index] = SavedFirebaseApp(name: trimmedName, appID: identifier)
    } else {
      apps.append(SavedFirebaseApp(name: trimmedName, appID: identifier))
    }
    try save(apps)
  }

  public func remove(name: String) throws {
    var apps = try load()
    guard
      let index = apps.firstIndex(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
    else { throw SimctlBuddyError.firebaseAppNotFound(name) }
    apps.remove(at: index)
    try save(apps)
  }

  public func app(named name: String) throws -> SavedFirebaseApp {
    guard
      let match = try load().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
    else { throw SimctlBuddyError.firebaseAppNotFound(name) }
    return match
  }

  /// Accepts either a saved name or a raw app identifier, so every command that
  /// takes an app can take both.
  public func resolve(_ selector: String) throws -> String {
    if let saved = try? app(named: selector) { return saved.appID }
    return try FirebaseApp.validate(selector)
  }

  private func save(_ apps: [SavedFirebaseApp]) throws {
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
