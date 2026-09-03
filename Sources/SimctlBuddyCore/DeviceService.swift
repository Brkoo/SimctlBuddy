import Foundation

/// One way in for both kinds of device.
///
/// Callers ask for an action on a device and this decides which tool runs it,
/// or refuses with an explanation when that kind of device cannot do it. Keeping
/// the decision here means the command line and the interface cannot disagree
/// about what is possible.
public struct DeviceService: Sendable {
  public let simctl: SimctlClient
  public let devicectl: DevicectlClient

  public init(
    simctl: SimctlClient = SimctlClient(),
    devicectl: DevicectlClient = DevicectlClient()
  ) {
    self.simctl = simctl
    self.devicectl = devicectl
  }

  // MARK: - Listing

  /// Simulators and physical devices together.
  ///
  /// A devicectl that is missing or unhappy must not take the simulator list
  /// down with it, so physical devices are best effort. Pass `strict` when the
  /// caller specifically asked about devices and silence would be misleading.
  public func devices(
    kinds: Set<DeviceKind> = Set(DeviceKind.allCases),
    strict: Bool = false
  ) throws -> [Device] {
    var result = [Device]()
    if kinds.contains(.simulator) {
      result += try simctl.devices()
    }
    if kinds.contains(.physical) {
      do {
        result += try devicectl.devices()
      } catch {
        if strict { throw error }
      }
    }
    return result.sorted {
      if $0.isBooted != $1.isBooted { return $0.isBooted }
      if $0.kind != $1.kind { return $0.kind == .simulator }
      if $0.runtimeName != $1.runtimeName { return $0.runtimeName > $1.runtimeName }
      return $0.name < $1.name
    }
  }

  public func resolveDevice(
    _ selector: String?,
    requireBooted: Bool = true,
    kinds: Set<DeviceKind> = Set(DeviceKind.allCases)
  ) throws -> Device {
    try DeviceResolver.resolve(
      selector: selector,
      devices: devices(kinds: kinds),
      requireBooted: requireBooted
    )
  }

  // MARK: - Capability gate

  public func require(_ capability: DeviceCapability, on device: Device) throws {
    guard device.supports(capability) else {
      throw SimctlBuddyError.unsupportedAction(capability, kind: device.kind)
    }
    if let reason = device.unreadyReason {
      throw SimctlBuddyError.setupProblem(reason)
    }
  }

  // MARK: - Actions

  public func openURL(_ value: String, device: Device) throws {
    try require(.openURL, on: device)
    switch device.kind {
    case .simulator: try simctl.openURL(value, device: device)
    case .physical: try devicectl.openURL(value, device: device)
    }
  }

  /// Installs a build, refusing one made for the other kind of device before
  /// the underlying tool gets a chance to fail obscurely.
  @discardableResult
  public func install(appAt path: String, device: Device) throws -> AppBundle {
    try require(.install, on: device)
    let bundle = try AppBundle.read(at: path)
    try bundle.checkInstallable(on: device.kind)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl(["install", device.udid, bundle.path])
    case .physical:
      try devicectl.install(appAt: bundle.path, device: device)
    }
    return bundle
  }

  @discardableResult
  public func launch(
    _ bundleIdentifier: String,
    device: Device,
    arguments: [String] = [],
    restart: Bool = false
  ) throws -> String {
    try require(.launch, on: device)
    switch device.kind {
    case .simulator:
      if restart {
        _ = try? simctl.simctl(["terminate", device.udid, bundleIdentifier])
      }
      return try simctl.simctl(["launch", device.udid, bundleIdentifier] + arguments)
    case .physical:
      return try devicectl.launch(
        bundleIdentifier, device: device, arguments: arguments, terminateExisting: restart)
    }
  }

  public func terminate(_ bundleIdentifier: String, device: Device) throws {
    try require(.terminate, on: device)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl(["terminate", device.udid, bundleIdentifier])
    case .physical:
      try devicectl.terminate(bundleIdentifier, device: device)
    }
  }

  public func installedBundleIdentifiers(device: Device) throws -> [String] {
    try require(.listApps, on: device)
    switch device.kind {
    case .simulator: return try simctl.installedBundleIdentifiers(device: device)
    case .physical: return try devicectl.installedBundleIdentifiers(device: device)
    }
  }

  public func runningBundleIdentifiers(device: Device) throws -> [String] {
    try require(.runningApps, on: device)
    switch device.kind {
    case .simulator: return try simctl.runningBundleIdentifiers(device: device)
    case .physical: return try devicectl.runningBundleIdentifiers(device: device)
    }
  }

  public func screenshot(to path: String, device: Device) throws {
    try require(.screenshot, on: device)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl(["io", device.udid, "screenshot", path])
    case .physical:
      try devicectl.screenshot(to: path, device: device)
    }
  }

  /// Adds the physical-device side to `simctl`'s own checks.
  public func diagnostics() throws -> [String] {
    var lines = try simctl.diagnostics()
    guard devicectl.isAvailable else {
      lines.append("devicectl is not available, so physical devices cannot be used")
      return lines
    }
    if let version = try? devicectl.version(), !version.isEmpty {
      lines.append("devicectl \(version) is available")
    } else {
      lines.append("devicectl is available")
    }

    if let devices = try? devicectl.devices() {
      let connected = devices.filter(\.isConnected)
      lines.append(
        "Found \(devices.count) paired device\(devices.count == 1 ? "" : "s"), "
          + "\(connected.count) connected")
      for device in connected {
        var notes = [device.runtimeName]
        if device.isWireless { notes.append("wireless") }
        if device.developerModeEnabled == false { notes.append("Developer Mode off") }
        lines.append("Connected: \(device.name) [\(notes.joined(separator: " · "))]")
      }
      // Developer Mode off is the thing that silently breaks installing.
      for device in devices where device.developerModeEnabled == false {
        lines.append(
          "\(device.name) has Developer Mode off: Settings › Privacy & Security › Developer Mode")
      }
    } else {
      lines.append("devicectl could not list devices")
    }
    return lines
  }

  public func reboot(device: Device) throws {
    try require(.reboot, on: device)
    try devicectl.reboot(device: device)
  }

  public func setAppearance(_ appearance: String, device: Device) throws {
    try require(.appearance, on: device)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl(["ui", device.udid, "appearance", appearance])
    case .physical:
      try devicectl.setAppearance(appearance, device: device)
    }
  }

  public func setLocation(latitude: Double, longitude: Double, device: Device) throws {
    try require(.location, on: device)
    try simctl.validateCoordinate(latitude: latitude, longitude: longitude)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl([
        "location", device.udid, "set", "\(latitude),\(longitude)",
      ])
    case .physical:
      try devicectl.setLocation(latitude: latitude, longitude: longitude, device: device)
    }
  }

  public func clearLocation(device: Device) throws {
    try require(.location, on: device)
    switch device.kind {
    case .simulator: _ = try simctl.simctl(["location", device.udid, "clear"])
    case .physical: try devicectl.clearLocation(device: device)
    }
  }

  public func applyCleanStatusBar(device: Device) throws {
    try require(.statusBar, on: device)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl([
        "status_bar", device.udid, "override",
        "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
        "--wifiBars", "3", "--cellularBars", "4",
      ])
    case .physical:
      try devicectl.applyCleanStatusBar(device: device)
    }
  }

  public func clearStatusBar(device: Device) throws {
    try require(.statusBar, on: device)
    switch device.kind {
    case .simulator: _ = try simctl.simctl(["status_bar", device.udid, "clear"])
    case .physical: try devicectl.clearStatusBar(device: device)
    }
  }

  public func copyToClipboard(_ text: String, device: Device) throws {
    try require(.clipboard, on: device)
    switch device.kind {
    case .simulator:
      _ = try simctl.simctl(["pbcopy", device.udid], standardInput: Data(text.utf8))
    case .physical:
      try devicectl.copyToClipboard(text, device: device)
    }
  }

  public func readClipboard(device: Device) throws -> String {
    try require(.clipboard, on: device)
    switch device.kind {
    case .simulator: return try simctl.simctl(["pbpaste", device.udid])
    case .physical: return try devicectl.readClipboard(device: device)
    }
  }
}
