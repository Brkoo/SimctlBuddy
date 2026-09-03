import Foundation

/// What happened when a build was installed from App Distribution.
public struct FirebaseInstallReport: Sendable {
  public let release: FirebaseRelease
  public let bundle: AppBundle
  public let profile: ProvisioningProfile?
  public let device: Device
  /// Things worth saying that did not stop the install.
  public var notes: [String] = []

  public init(
    release: FirebaseRelease,
    bundle: AppBundle,
    profile: ProvisioningProfile?,
    device: Device,
    notes: [String] = []
  ) {
    self.release = release
    self.bundle = bundle
    self.profile = profile
    self.device = device
    self.notes = notes
  }
}

/// Installing App Distribution builds onto a connected device.
///
/// The chain is: list releases, download the signed binary, unpack the app out
/// of the `.ipa`, check the build is actually signed for this device, then hand
/// it to the same install path a local build takes.
public struct FirebaseDistribution: Sendable {
  private let client: FirebaseClient
  private let service: DeviceService
  private let store: FirebaseStore
  private let pathStore: PathStore
  private let runner: any CommandRunning

  public init(
    client: FirebaseClient = FirebaseClient(),
    service: DeviceService = DeviceService(),
    store: FirebaseStore = FirebaseStore(),
    pathStore: PathStore = PathStore(),
    runner: any CommandRunning = ProcessRunner()
  ) {
    self.client = client
    self.service = service
    self.store = store
    self.pathStore = pathStore
    self.runner = runner
  }

  // MARK: - Reading

  public func releases(
    app selector: String,
    limit: Int = 50,
    filter: String? = nil
  ) throws -> [FirebaseRelease] {
    let appID = try store.resolve(selector)
    return try client.releases(appID: appID, limit: limit, filter: filter)
  }

  public func apps(projectID: String) throws -> [FirebaseApp] {
    try client.iosApps(projectID: projectID)
  }

  public func projects() throws -> [(id: String, name: String)] {
    try client.projects()
  }

  /// Every reachable iOS app, grouped by project.
  public func allApps() throws -> [FirebaseProjectApps] {
    try client.allIOSApps()
  }

  // MARK: - Fetching a build

  /// Downloads and unpacks a release, reusing an earlier download when the same
  /// build was already fetched.
  public func prepare(
    _ release: FirebaseRelease,
    appID: String
  ) throws -> (bundle: AppBundle, profile: ProvisioningProfile?) {
    let root = Self.cacheDirectory(for: appID, release: release)
    let archive = root.appendingPathComponent(release.suggestedFileName)
    let unpacked = root.appendingPathComponent("unpacked", isDirectory: true)

    if let existing = cachedBundle(in: unpacked) {
      return (existing, try ProvisioningProfile.read(inAppBundleAt: existing.path, runner: runner))
    }

    if !FileManager.default.fileExists(atPath: archive.path) {
      try client.download(release, to: archive)
    }
    let bundle = try AppArchive.extractApp(from: archive.path, into: unpacked, runner: runner)
    // The archive is the big half and is no longer needed once unpacked.
    try? FileManager.default.removeItem(at: archive)
    return (bundle, try ProvisioningProfile.read(inAppBundleAt: bundle.path, runner: runner))
  }

  // MARK: - Installing

  /// Downloads a release and installs it, refusing a build that is not signed
  /// for this device unless the caller insists.
  public func install(
    _ release: FirebaseRelease,
    appID: String,
    on device: Device,
    force: Bool = false
  ) throws -> FirebaseInstallReport {
    guard device.kind == .physical else {
      throw SimctlBuddyError.firebaseNeedsPhysicalDevice
    }
    let (bundle, profile) = try prepare(release, appID: appID)

    var notes = [String]()
    if let profile {
      if !force, !profile.permits(hardwareUDID: device.hardwareUDID) {
        throw SimctlBuddyError.deviceNotInProfile(
          release: release.versionLabel,
          device: device.name,
          profile: profile.name ?? "the build's profile",
          deviceCount: profile.provisionedDevices.count
        )
      }
      if profile.isExpired {
        notes.append("The build's provisioning profile has expired, so it may refuse to launch.")
      }
      if profile.provisionsAllDevices {
        notes.append("Enterprise build: it installs on any device.")
      }
    }

    try service.install(appAt: bundle.path, device: device)
    try? pathStore.recordRecent(bundle.path)
    return FirebaseInstallReport(
      release: release,
      bundle: bundle,
      profile: profile,
      device: device,
      notes: notes
    )
  }

  /// Installs a build named by its release ID, looking it up first.
  ///
  /// The interface only carries identifiers between screens, so the release has
  /// to be found again rather than held on to — and the download link would
  /// have expired anyway.
  public func install(
    releaseID: String,
    app selector: String,
    on device: Device,
    force: Bool = false
  ) throws -> FirebaseInstallReport {
    let appID = try store.resolve(selector)
    let available = try client.releases(appID: appID, limit: 100)
    guard let release = available.first(where: { $0.releaseID == releaseID }) else {
      throw SimctlBuddyError.releaseHasNoBinary(releaseID)
    }
    return try install(release, appID: appID, on: device, force: force)
  }

  // MARK: - Cache

  private func cachedBundle(in directory: URL) -> AppBundle? {
    let payload = directory.appendingPathComponent("Payload", isDirectory: true)
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: payload, includingPropertiesForKeys: nil),
      let app = contents.first(where: { $0.pathExtension == "app" })
    else { return nil }
    return try? AppBundle.read(at: app.path)
  }

  static func cacheDirectory(for appID: String, release: FirebaseRelease) -> URL {
    let safeApp = appID.replacingOccurrences(of: ":", with: "-")
    return AppArchive.cacheDirectory
      .appendingPathComponent(safeApp, isDirectory: true)
      .appendingPathComponent(release.releaseID.isEmpty ? "current" : release.releaseID,
        isDirectory: true)
  }
}
