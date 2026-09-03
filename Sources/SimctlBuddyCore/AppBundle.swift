import Foundation

/// What a built `.app` bundle can be installed on.
///
/// On Apple silicon both builds are arm64, so the architecture says nothing.
/// What separates them is `DTPlatformName` in the bundle's Info.plist, and the
/// provisioning profile a device build has to carry.
public struct AppBundle: Equatable, Sendable {
  public enum Platform: String, Equatable, Sendable {
    case simulator = "iphonesimulator"
    case device = "iphoneos"
    case unknown

    public var kind: DeviceKind? {
      switch self {
      case .simulator: return .simulator
      case .device: return .physical
      case .unknown: return nil
      }
    }
  }

  public let path: String
  public let platform: Platform
  public let hasProvisioningProfile: Bool
  public let bundleIdentifier: String?

  public init(
    path: String,
    platform: Platform,
    hasProvisioningProfile: Bool,
    bundleIdentifier: String? = nil
  ) {
    self.path = path
    self.platform = platform
    self.hasProvisioningProfile = hasProvisioningProfile
    self.bundleIdentifier = bundleIdentifier
  }

  public var name: String {
    URL(fileURLWithPath: path).lastPathComponent
  }

  /// Reads what can be learned from the bundle on disk.
  public static func read(at path: String) throws -> AppBundle {
    let resolved = try validate(at: path)
    let url = URL(fileURLWithPath: resolved)
    let plist = url.appendingPathComponent("Info.plist")

    var platform = Platform.unknown
    var identifier: String?
    if let data = try? Data(contentsOf: plist),
      let info = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any]
    {
      if let name = info["DTPlatformName"] as? String {
        platform = Platform(rawValue: name.lowercased()) ?? .unknown
      }
      identifier = info["CFBundleIdentifier"] as? String
    }

    let profile = url.appendingPathComponent("embedded.mobileprovision")
    let hasProfile = FileManager.default.fileExists(atPath: profile.path)
    // An older or stripped bundle may not say, so the profile settles it.
    if platform == .unknown, hasProfile { platform = .device }

    return AppBundle(
      path: resolved,
      platform: platform,
      hasProvisioningProfile: hasProfile,
      bundleIdentifier: identifier
    )
  }

  /// Checks the bundle exists and looks like an app bundle.
  public static func validate(at path: String) throws -> String {
    let expanded = NSString(string: path).expandingTildeInPath
    let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory),
      isDirectory.boolValue,
      absolute.hasSuffix(".app")
    else { throw SimctlBuddyError.invalidAppBundle(absolute) }
    return absolute
  }

  /// Refuses a bundle built for the other kind of device, with the fix rather
  /// than the signing error the underlying tool would produce.
  public func checkInstallable(on kind: DeviceKind) throws {
    guard let built = platform.kind, built != kind else {
      if kind == .physical, platform == .simulator {
        throw SimctlBuddyError.wrongBuildForDevice(name: name, kind: kind, hint: Self.hint(for: kind))
      }
      return
    }
    throw SimctlBuddyError.wrongBuildForDevice(
      name: name, kind: kind, hint: Self.hint(for: kind))
  }

  private static func hint(for kind: DeviceKind) -> String {
    switch kind {
    case .physical:
      return
        "That is a simulator build. The device build is usually the -iphoneos folder beside it, and has to be signed for this device."
    case .simulator:
      return "That is a device build. The simulator build is usually the -iphonesimulator folder beside it."
    }
  }
}
