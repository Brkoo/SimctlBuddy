import Foundation

/// What a build's embedded provisioning profile permits.
///
/// Worth reading before an install rather than after: iOS decides whether a
/// build may run on a device from the profile that was baked in at build time,
/// and the failure it produces otherwise says only that installation failed.
public struct ProvisioningProfile: Equatable, Sendable {
  public let name: String?
  public let teamName: String?
  public let expirationDate: Date?
  /// Enterprise profiles carry no device list and install anywhere.
  public let provisionsAllDevices: Bool
  public let provisionedDevices: [String]

  public init(
    name: String? = nil,
    teamName: String? = nil,
    expirationDate: Date? = nil,
    provisionsAllDevices: Bool = false,
    provisionedDevices: [String] = []
  ) {
    self.name = name
    self.teamName = teamName
    self.expirationDate = expirationDate
    self.provisionsAllDevices = provisionsAllDevices
    self.provisionedDevices = provisionedDevices
  }

  public var isExpired: Bool {
    guard let expirationDate else { return false }
    return expirationDate < Date()
  }

  /// Whether this build can install on a device, given its hardware UDID.
  ///
  /// A device whose UDID is unknown cannot be judged, so it is allowed through
  /// rather than blocked on a guess.
  public func permits(hardwareUDID: String?) -> Bool {
    if provisionsAllDevices { return true }
    guard let hardwareUDID, !hardwareUDID.isEmpty else { return true }
    if provisionedDevices.isEmpty { return true }
    return provisionedDevices.contains { $0.caseInsensitiveCompare(hardwareUDID) == .orderedSame }
  }

  /// Reads the profile inside an installed or extracted `.app`.
  ///
  /// The profile is CMS-signed, so it is decoded with `security` rather than
  /// read as a plist directly.
  public static func read(
    inAppBundleAt path: String,
    runner: any CommandRunning = ProcessRunner()
  ) throws -> ProvisioningProfile? {
    let profilePath = URL(fileURLWithPath: path)
      .appendingPathComponent("embedded.mobileprovision").path
    guard FileManager.default.fileExists(atPath: profilePath) else { return nil }

    let result = try runner.run(
      executable: "/usr/bin/security",
      arguments: ["cms", "-D", "-i", profilePath]
    )
    guard result.exitCode == 0, let data = result.standardOutput.data(using: .utf8) else {
      return nil
    }
    guard
      let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
      let info = plist as? [String: Any]
    else { return nil }

    return ProvisioningProfile(
      name: info["Name"] as? String,
      teamName: info["TeamName"] as? String,
      expirationDate: info["ExpirationDate"] as? Date,
      provisionsAllDevices: info["ProvisionsAllDevices"] as? Bool ?? false,
      provisionedDevices: info["ProvisionedDevices"] as? [String] ?? []
    )
  }
}

/// Unpacks the `.ipa` files App Distribution hands out.
///
/// `devicectl install app` documents a `.app` bundle as its input, so the app
/// is lifted out of `Payload/` and installed as one. That also means the usual
/// `AppBundle` checks apply to a downloaded build exactly as they do to a local
/// one.
public enum AppArchive {
  /// Where downloaded builds live between runs, so re-installing the same build
  /// does not download it twice.
  public static var cacheDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Caches/simbuddy/firebase", isDirectory: true)
  }

  /// Unzips an `.ipa` and returns the app bundle inside it.
  @discardableResult
  public static func extractApp(
    from archivePath: String,
    into directory: URL,
    runner: any CommandRunning = ProcessRunner()
  ) throws -> AppBundle {
    guard FileManager.default.fileExists(atPath: archivePath) else {
      throw SimctlBuddyError.missingFile(archivePath)
    }
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let result = try runner.run(
      executable: "/usr/bin/unzip",
      arguments: ["-q", "-o", archivePath, "-d", directory.path]
    )
    guard result.exitCode == 0 else {
      throw SimctlBuddyError.invalidArchive(
        "Unpacking the build failed: \(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }

    let payload = directory.appendingPathComponent("Payload", isDirectory: true)
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: payload,
        includingPropertiesForKeys: nil
      )) ?? []
    guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
      throw SimctlBuddyError.invalidArchive(
        "That build contains no app bundle. App Distribution serves .ipa files for iOS; an Android build cannot be installed on a device here."
      )
    }
    return try AppBundle.read(at: app.path)
  }

  /// Clears cached downloads and returns how many bytes were freed.
  @discardableResult
  public static func clearCache() throws -> UInt64 {
    let directory = cacheDirectory
    guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
    let size = directorySize(directory)
    try FileManager.default.removeItem(at: directory)
    return size
  }

  private static func directorySize(_ directory: URL) -> UInt64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey]
      )
    else { return 0 }
    var total: UInt64 = 0
    for case let url as URL in enumerator {
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      total += UInt64(size)
    }
    return total
  }
}
