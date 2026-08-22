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
