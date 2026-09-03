import Foundation

/// An app installed on a physical device.
public struct DeviceApp: Equatable, Sendable {
  public let bundleIdentifier: String
  public let name: String
  /// Where the bundle lives, which is how a running process is matched back to
  /// the app it belongs to.
  public let bundleURL: String?
  public let version: String?
  public let builtByDeveloper: Bool

  public init(
    bundleIdentifier: String,
    name: String,
    bundleURL: String? = nil,
    version: String? = nil,
    builtByDeveloper: Bool = false
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.name = name
    self.bundleURL = bundleURL
    self.version = version
    self.builtByDeveloper = builtByDeveloper
  }
}

/// Drives physical devices through `xcrun devicectl`.
///
/// Unlike simctl, devicectl documents a file written with `--json-output` as the
/// only supported way for a program to read its results, so every call here
/// writes JSON to a temporary file and parses that rather than reading stdout.
public struct DevicectlClient: Sendable {
  private let runner: any CommandRunning
  private let xcrunPath: String

  public init(
    runner: any CommandRunning = ProcessRunner(),
    xcrunPath: String = "/usr/bin/xcrun"
  ) {
    self.runner = runner
    self.xcrunPath = xcrunPath
  }

  /// Whether this machine has a devicectl at all. Xcode 15 and later do.
  public var isAvailable: Bool {
    guard
      let result = try? runner.run(executable: xcrunPath, arguments: ["-f", "devicectl"])
    else { return false }
    return result.exitCode == 0
  }

  public func version() throws -> String {
    let result = try runner.run(
      executable: xcrunPath, arguments: ["devicectl", "--version"])
    return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Devices

  /// Physical devices only.
  ///
  /// devicectl lists simulators too, marked `reality: simulated`; including them
  /// would show every simulator twice, once from each tool.
  public func devices() throws -> [Device] {
    let data = try run(["list", "devices"])
    return try Self.parseDevices(data)
  }

  static func parseDevices(_ data: Data) throws -> [Device] {
    guard
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let entries = result["devices"] as? [[String: Any]]
    else { throw SimctlBuddyError.invalidResponse("devicectl did not return a device list.") }

    return entries.compactMap(device(from:))
      .sorted {
        if $0.isConnected != $1.isConnected { return $0.isConnected }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  private static func device(from entry: [String: Any]) -> Device? {
    let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
    guard (hardware["reality"] as? String) == "physical" else { return nil }
    guard let identifier = entry["identifier"] as? String else { return nil }

    let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
    let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
    let name = properties["name"] as? String ?? hardware["marketingName"] as? String ?? identifier
    let tunnel = connection["tunnelState"] as? String
    let transport = connection["transportType"] as? String
    let isConnected = tunnel == "connected"

    return Device(
      name: name,
      udid: identifier,
      // A phone has no boot state worth showing; whether it can be reached does.
      state: isConnected ? "Connected" : (tunnel == "unavailable" ? "Unavailable" : "Disconnected"),
      isAvailable: (connection["pairingState"] as? String) == "paired",
      kind: .physical,
      deviceTypeIdentifier: hardware["productType"] as? String,
      osVersion: properties["osVersionNumber"] as? String,
      modelName: hardware["marketingName"] as? String,
      hardwareUDID: hardware["udid"] as? String,
      isConnected: isConnected,
      isWireless: transport == "localNetwork",
      developerModeEnabled: (properties["developerModeStatus"] as? String) == "enabled"
    )
  }

  // MARK: - Apps

  public func installedApps(device: Device) throws -> [DeviceApp] {
    let data = try run(["device", "info", "apps", "--device", device.udid])
    return try Self.parseApps(data)
  }

  static func parseApps(_ data: Data) throws -> [DeviceApp] {
    guard
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let entries = result["apps"] as? [[String: Any]]
    else { throw SimctlBuddyError.invalidResponse("devicectl did not return an app list.") }

    return entries.compactMap { entry in
      guard let identifier = entry["bundleIdentifier"] as? String else { return nil }
      return DeviceApp(
        bundleIdentifier: identifier,
        name: entry["name"] as? String ?? identifier,
        bundleURL: entry["url"] as? String,
        version: entry["version"] as? String,
        builtByDeveloper: entry["builtByDeveloper"] as? Bool ?? false
      )
    }
    .sorted { $0.bundleIdentifier < $1.bundleIdentifier }
  }

  public func installedBundleIdentifiers(device: Device) throws -> [String] {
    try installedApps(device: device).map(\.bundleIdentifier)
  }

  /// Which apps are running, worked out by matching each running process against
  /// the app bundles on the device — devicectl reports executables, not owners.
  public func runningBundleIdentifiers(device: Device) throws -> [String] {
    let apps = try installedApps(device: device)
    let processes = try self.processes(device: device)
    return Self.match(processes: processes, to: apps)
      .map(\.bundleIdentifier)
      .sorted()
  }

  public func processIdentifier(
    forBundleIdentifier bundleIdentifier: String,
    device: Device
  ) throws -> Int32 {
    let apps = try installedApps(device: device)
    guard
      let app = apps.first(where: {
        $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
      })
    else { throw SimctlBuddyError.appNotInstalled(bundleIdentifier, device: device.name) }

    let processes = try self.processes(device: device)
    guard let match = Self.match(processes: processes, to: [app]).first else {
      throw SimctlBuddyError.appNotRunning(bundleIdentifier, device: device.name)
    }
    return match.processIdentifier
  }

  struct RunningProcess: Equatable, Sendable {
    let processIdentifier: Int32
    let executable: String
  }

  struct RunningApp: Equatable, Sendable {
    let bundleIdentifier: String
    let processIdentifier: Int32
  }

  func processes(device: Device) throws -> [RunningProcess] {
    let data = try run(["device", "info", "processes", "--device", device.udid])
    return try Self.parseProcesses(data)
  }

  static func parseProcesses(_ data: Data) throws -> [RunningProcess] {
    guard
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let entries = result["runningProcesses"] as? [[String: Any]]
    else {
      throw SimctlBuddyError.invalidResponse("devicectl did not return a process list.")
    }

    return entries.compactMap { entry in
      guard let pid = entry["processIdentifier"] as? Int else { return nil }
      return RunningProcess(
        processIdentifier: Int32(pid),
        executable: entry["executable"] as? String ?? ""
      )
    }
  }

  /// A process belongs to an app when its executable sits inside the app's
  /// bundle.
  static func match(processes: [RunningProcess], to apps: [DeviceApp]) -> [RunningApp] {
    var result = [RunningApp]()
    for app in apps {
      guard let bundle = app.bundleURL, !bundle.isEmpty else { continue }
      let prefix = bundle.hasSuffix("/") ? bundle : bundle + "/"
      guard
        let process = processes.first(where: { $0.executable.hasPrefix(prefix) })
      else { continue }
      result.append(
        RunningApp(
          bundleIdentifier: app.bundleIdentifier,
          processIdentifier: process.processIdentifier))
    }
    return result
  }

  // MARK: - Actions

  public func openURL(_ value: String, device: Device) throws {
    guard SimctlClient.isValidDeepLink(value) else { throw SimctlBuddyError.invalidURL(value) }
    _ = try run(["device", "process", "openURL", "--device", device.udid, value])
  }

  public func install(appAt path: String, device: Device) throws {
    _ = try run(["device", "install", "app", "--device", device.udid, path])
  }

  @discardableResult
  public func launch(
    _ bundleIdentifier: String,
    device: Device,
    arguments: [String] = [],
    terminateExisting: Bool = false
  ) throws -> String {
    var command = ["device", "process", "launch", "--device", device.udid]
    if terminateExisting { command.append("--terminate-existing") }
    command.append(bundleIdentifier)
    command += arguments
    let data = try run(command)
    if let pid = Self.parseLaunchedProcessIdentifier(data) {
      return "pid \(pid)"
    }
    return ""
  }

  static func parseLaunchedProcessIdentifier(_ data: Data) -> Int32? {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = root["result"] as? [String: Any],
      let process = result["process"] as? [String: Any],
      let pid = process["processIdentifier"] as? Int
    else { return nil }
    return Int32(pid)
  }

  /// devicectl terminates a process, not an app, so the pid has to be found
  /// first.
  public func terminate(_ bundleIdentifier: String, device: Device) throws {
    let pid = try processIdentifier(forBundleIdentifier: bundleIdentifier, device: device)
    _ = try run([
      "device", "process", "terminate", "--device", device.udid, "--pid", String(pid),
    ])
  }

  public func screenshot(to path: String, device: Device) throws {
    _ = try run([
      "device", "capture", "screenshot", "--device", device.udid, "--destination", path,
    ])
  }

  public func reboot(device: Device) throws {
    _ = try run(["device", "reboot", "--device", device.udid])
  }

  public func setAppearance(_ appearance: String, device: Device) throws {
    _ = try run([
      "device", "settings", "appearance", "--device", device.udid, "--mode", appearance,
    ])
  }

  public func setLocation(latitude: Double, longitude: Double, device: Device) throws {
    _ = try run([
      "device", "simulate", "location", "coordinate", "--device", device.udid,
      "--latitude", String(latitude), "--longitude", String(longitude),
    ])
  }

  public func clearLocation(device: Device) throws {
    _ = try run(["device", "simulate", "location", "clear", "--device", device.udid])
  }

  /// The same 9:41 status bar simctl offers, in devicectl's spelling.
  public func applyCleanStatusBar(device: Device) throws {
    _ = try run([
      "device", "simulate", "statusBar", "override", "--device", device.udid,
      "--time", "9:41",
      "--battery-state", "charged",
      "--battery-level", "100",
      "--wifi-mode", "active",
      "--wifi-strength", "3",
      "--cellular-mode", "active",
      "--cellular-strength", "4",
    ])
  }

  public func clearStatusBar(device: Device) throws {
    _ = try run(["device", "simulate", "statusBar", "clear", "--device", device.udid])
  }

  /// devicectl copies from a file rather than standard input, so the text is
  /// written to a temporary one.
  public func copyToClipboard(_ text: String, device: Device) throws {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("simbuddy-paste-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let file = scratch.appendingPathComponent("clipboard.txt")
    try Data(text.utf8).write(to: file)

    _ = try run([
      "device", "pasteboard", "copy", "--device", device.udid,
      "--type", "public.utf8-plain-text", "--file", file.path,
    ])
  }

  public func readClipboard(device: Device) throws -> String {
    let data = try run([
      "device", "pasteboard", "paste", "--device", device.udid,
      "--type", "public.utf8-plain-text",
    ])
    return Self.parseClipboard(data)
  }

  static func parseClipboard(_ data: Data) -> String {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = root["result"] as? [String: Any]
    else { return "" }

    // The payload has moved around between releases, so accept the shapes seen
    // rather than insisting on one.
    if let text = result["contents"] as? String { return text }
    if let items = result["items"] as? [[String: Any]] {
      let strings = items.compactMap { item -> String? in
        if let text = item["contents"] as? String { return text }
        if let text = item["data"] as? String,
          let decoded = Data(base64Encoded: text)
        {
          return String(decoding: decoded, as: UTF8.self)
        }
        return nil
      }
      return strings.joined(separator: "\n")
    }
    if let text = result["data"] as? String, let decoded = Data(base64Encoded: text) {
      return String(decoding: decoded, as: UTF8.self)
    }
    return ""
  }

  // MARK: - Plumbing

  /// Runs devicectl and returns the JSON it wrote.
  @discardableResult
  private func run(_ arguments: [String]) throws -> Data {
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("simbuddy-devicectl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let output = scratch.appendingPathComponent("result.json")

    let result = try runner.run(
      executable: xcrunPath,
      arguments: ["devicectl"] + arguments + ["--json-output", output.path],
      standardInput: nil
    )

    guard result.exitCode == 0 else {
      let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      throw SimctlBuddyError.commandFailed(
        command: (["xcrun", "devicectl"] + arguments).joined(separator: " "),
        exitCode: result.exitCode,
        message: message.isEmpty ? result.standardOutput : message
      )
    }
    return (try? Data(contentsOf: output)) ?? Data()
  }
}
