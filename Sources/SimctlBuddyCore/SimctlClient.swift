import Foundation

public struct SimctlClient: Sendable {
  private let runner: any CommandRunning
  private let xcrunPath: String

  public init(
    runner: any CommandRunning = ProcessRunner(),
    xcrunPath: String = "/usr/bin/xcrun"
  ) {
    self.runner = runner
    self.xcrunPath = xcrunPath
  }

  @discardableResult
  public func simctl(_ arguments: [String], standardInput: Data? = nil) throws -> String {
    let result = try runner.run(
      executable: xcrunPath,
      arguments: ["simctl"] + arguments,
      standardInput: standardInput
    )
    guard result.exitCode == 0 else {
      let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
      throw SimctlBuddyError.commandFailed(
        command: (["xcrun", "simctl"] + arguments).joined(separator: " "),
        exitCode: result.exitCode,
        message: message.isEmpty ? result.standardOutput : message
      )
    }
    return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func devices() throws -> [SimulatorDevice] {
    let output = try simctl(["list", "devices", "available", "--json"])
    guard let data = output.data(using: .utf8) else {
      throw SimctlBuddyError.invalidResponse("Output was not UTF-8.")
    }

    do {
      let response = try JSONDecoder().decode(DeviceListResponse.self, from: data)
      return response.devices.flatMap { runtime, devices in
        devices.map { device in
          var copy = device
          copy.runtimeIdentifier = runtime
          return copy
        }
      }
      .sorted {
        if $0.isBooted != $1.isBooted { return $0.isBooted }
        if $0.runtimeName != $1.runtimeName { return $0.runtimeName > $1.runtimeName }
        return $0.name < $1.name
      }
    } catch {
      throw SimctlBuddyError.invalidResponse(error.localizedDescription)
    }
  }

  public func resolveDevice(_ selector: String?, requireBooted: Bool = true) throws
    -> SimulatorDevice
  {
    try DeviceResolver.resolve(
      selector: selector,
      devices: devices(),
      requireBooted: requireBooted
    )
  }

  public func boot(selector: String?, openSimulator: Bool = true) throws -> SimulatorDevice {
    let device: SimulatorDevice
    if let selector {
      device = try resolveDevice(selector, requireBooted: false)
    } else {
      let available = try devices().filter(\.isAvailable)
      if let booted = available.first(where: \.isBooted) {
        device = booted
      } else if let newestPhone = available.first(where: { $0.name.hasPrefix("iPhone") }) {
        device = newestPhone
      } else if let first = available.first {
        device = first
      } else {
        throw SimctlBuddyError.deviceNotFound("any available simulator")
      }
    }

    if !device.isBooted {
      _ = try simctl(["boot", device.udid])
      _ = try simctl(["bootstatus", device.udid, "-b"])
    }

    if openSimulator {
      let result = try runner.run(
        executable: "/usr/bin/open",
        arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid]
      )
      if result.exitCode != 0 {
        throw SimctlBuddyError.commandFailed(
          command: "open -a Simulator",
          exitCode: result.exitCode,
          message: result.standardError
        )
      }
    }
    return device
  }

  public func openURL(_ value: String, device: SimulatorDevice) throws {
    guard Self.isValidDeepLink(value) else { throw SimctlBuddyError.invalidURL(value) }
    _ = try simctl(["openurl", device.udid, value])
  }

  public static func isValidDeepLink(_ value: String) -> Bool {
    guard
      let components = URLComponents(string: value),
      let scheme = components.scheme,
      !scheme.isEmpty
    else { return false }
    return scheme.first?.isLetter == true
      && scheme.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
  }

  public func validateCoordinate(latitude: Double, longitude: Double) throws {
    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
      throw SimctlBuddyError.invalidCoordinate(latitude: latitude, longitude: longitude)
    }
  }

  /// Checks the local Xcode and Simulator setup, returning one line per check.
  /// Shared by the `doctor` command and the interactive interface.
  public func diagnostics() throws -> [String] {
    let developerDir = try runner.run(executable: "/usr/bin/xcode-select", arguments: ["-p"])
    guard developerDir.exitCode == 0 else {
      throw SimctlBuddyError.setupProblem(
        "Xcode command-line tools are not selected. Run `sudo xcode-select -s /Applications/Xcode.app`."
      )
    }
    var lines = [
      "Developer directory: "
        + developerDir.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    ]

    let help = try runner.run(executable: xcrunPath, arguments: ["simctl", "help"])
    guard help.exitCode == 0 else {
      throw SimctlBuddyError.setupProblem(
        "xcrun could not start simctl. Open Xcode once and finish installing components.")
    }
    lines.append("simctl is available")

    let available = try devices()
    lines.append("Found \(available.count) available simulator\(available.count == 1 ? "" : "s")")
    if let booted = available.first(where: \.isBooted) {
      lines.append("Booted: \(booted.name) [\(booted.runtimeName)]")
    } else {
      lines.append("No simulator is currently booted")
    }
    return lines
  }

  /// Bundle identifiers of the apps installed on a device, sorted for display.
  public func installedBundleIdentifiers(device: SimulatorDevice) throws -> [String] {
    let output = try simctl(["listapps", device.udid])
    var identifiers = Set<String>()
    for line in output.split(separator: "\n") {
      guard line.contains("CFBundleIdentifier") else { continue }
      let parts = line.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { continue }
      let value = parts[1]
        .trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: ";\""))
      if !value.isEmpty { identifiers.insert(value) }
    }
    return identifiers.sorted()
  }

  /// Bundle identifiers of the apps running on a device right now.
  ///
  /// simctl has no "list running apps", so this reads the simulator's own
  /// launchd: every foreground app is registered as a `UIKitApplication:` job.
  public func runningBundleIdentifiers(device: SimulatorDevice) throws -> [String] {
    let output = try simctl(["spawn", device.udid, "launchctl", "list"])
    return Self.parseRunningBundleIdentifiers(output)
  }

  /// Rows look like `88213  0  UIKitApplication:com.example.App[0x4f7c][rb-legacy]`.
  /// A dash in the PID column means the job is registered but not running.
  static func parseRunningBundleIdentifiers(_ output: String) -> [String] {
    let marker = "UIKitApplication:"
    var identifiers = Set<String>()
    for line in output.split(separator: "\n") {
      let columns = line.split(whereSeparator: \.isWhitespace)
      guard columns.count >= 3, Int(columns[0]) != nil else { continue }
      let label = columns[2 ..< columns.count].joined(separator: " ")
      guard let start = label.range(of: marker) else { continue }
      let rest = label[start.upperBound...]
      let identifier = String(rest.prefix(while: { $0 != "[" }))
      if AppStore.isValidBundleIdentifier(identifier) { identifiers.insert(identifier) }
    }
    return identifiers.sorted()
  }

  public func validateFile(at path: String) throws -> String {
    let expanded = NSString(string: path).expandingTildeInPath
    let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
    guard FileManager.default.fileExists(atPath: absolute) else {
      throw SimctlBuddyError.missingFile(absolute)
    }
    return absolute
  }

  public func validateAppBundle(at path: String) throws -> String {
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
}
