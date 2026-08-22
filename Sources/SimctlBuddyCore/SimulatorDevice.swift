import Foundation

public struct SimulatorDevice: Codable, Equatable, Sendable {
  public let name: String
  public let udid: String
  public let state: String
  public let isAvailable: Bool
  public let deviceTypeIdentifier: String?
  public var runtimeIdentifier: String?

  public init(
    name: String,
    udid: String,
    state: String,
    isAvailable: Bool,
    deviceTypeIdentifier: String? = nil,
    runtimeIdentifier: String? = nil
  ) {
    self.name = name
    self.udid = udid
    self.state = state
    self.isAvailable = isAvailable
    self.deviceTypeIdentifier = deviceTypeIdentifier
    self.runtimeIdentifier = runtimeIdentifier
  }

  public var isBooted: Bool {
    state.caseInsensitiveCompare("Booted") == .orderedSame
  }

  public var runtimeName: String {
    guard let runtimeIdentifier else { return "Unknown runtime" }
    let rawName =
      runtimeIdentifier
      .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
    let components = rawName.split(separator: "-").map(String.init)
    guard
      let versionStart = components.firstIndex(where: { component in
        !component.isEmpty && component.allSatisfy(\.isNumber)
      })
    else {
      return rawName.replacingOccurrences(of: "-", with: " ")
    }

    let platform = components[..<versionStart].joined(separator: " ")
    let version = components[versionStart...].joined(separator: ".")
    return "\(platform) \(version)"
  }
}

struct DeviceListResponse: Decodable {
  let devices: [String: [SimulatorDevice]]
}

public enum DeviceResolver {
  public static func resolve(
    selector: String?,
    devices: [SimulatorDevice],
    requireBooted: Bool
  ) throws -> SimulatorDevice {
    let available = devices.filter(\.isAvailable)

    guard let selector, !selector.isEmpty else {
      let booted = available.filter(\.isBooted)
      if booted.count == 1 { return booted[0] }
      if booted.isEmpty { throw SimctlBuddyError.noBootedDevice }
      throw SimctlBuddyError.ambiguousDevice(
        "booted",
        matches: booted.map { "\($0.name) [\($0.udid)]" }
      )
    }

    let candidates = requireBooted ? available.filter(\.isBooted) : available
    if let exactUDID = candidates.first(where: {
      $0.udid.caseInsensitiveCompare(selector) == .orderedSame
    }) {
      return exactUDID
    }
    if let exactName = candidates.first(where: {
      $0.name.caseInsensitiveCompare(selector) == .orderedSame
    }) {
      return exactName
    }

    let partial = candidates.filter {
      $0.name.localizedCaseInsensitiveContains(selector)
        || $0.udid.localizedCaseInsensitiveContains(selector)
    }
    if partial.count == 1 { return partial[0] }
    if partial.count > 1 {
      throw SimctlBuddyError.ambiguousDevice(
        selector,
        matches: partial.map { "\($0.name) [\($0.runtimeName)]" }
      )
    }
    throw SimctlBuddyError.deviceNotFound(selector)
  }
}
