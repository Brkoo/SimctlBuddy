import Foundation

/// A device SimctlBuddy can drive: a simulator or a physical one.
///
/// Both tools report different things, so the fields that only one of them has
/// are optional and the shared questions — is it ready, what is it running —
/// are answered through computed properties.
public struct Device: Codable, Equatable, Sendable {
  public let name: String
  /// The identifier the driving tool wants: a simulator UDID, or the UUID that
  /// `devicectl --device` accepts.
  public let udid: String
  public let state: String
  public let isAvailable: Bool
  public let kind: DeviceKind
  public let deviceTypeIdentifier: String?
  public var runtimeIdentifier: String?
  /// Physical devices only.
  public let osVersion: String?
  public let modelName: String?
  public let hardwareUDID: String?
  /// Whether the developer tooling can reach it right now.
  public let isConnected: Bool
  public let isWireless: Bool
  public let developerModeEnabled: Bool?

  public init(
    name: String,
    udid: String,
    state: String,
    isAvailable: Bool,
    kind: DeviceKind = .simulator,
    deviceTypeIdentifier: String? = nil,
    runtimeIdentifier: String? = nil,
    osVersion: String? = nil,
    modelName: String? = nil,
    hardwareUDID: String? = nil,
    isConnected: Bool = true,
    isWireless: Bool = false,
    developerModeEnabled: Bool? = nil
  ) {
    self.name = name
    self.udid = udid
    self.state = state
    self.isAvailable = isAvailable
    self.kind = kind
    self.deviceTypeIdentifier = deviceTypeIdentifier
    self.runtimeIdentifier = runtimeIdentifier
    self.osVersion = osVersion
    self.modelName = modelName
    self.hardwareUDID = hardwareUDID
    self.isConnected = isConnected
    self.isWireless = isWireless
    self.developerModeEnabled = developerModeEnabled
  }

  /// simctl's own JSON has none of the physical fields, so they decode as
  /// absent and the kind falls back to simulator.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    udid = try container.decode(String.self, forKey: .udid)
    state = try container.decode(String.self, forKey: .state)
    isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
    kind = try container.decodeIfPresent(DeviceKind.self, forKey: .kind) ?? .simulator
    deviceTypeIdentifier = try container.decodeIfPresent(
      String.self, forKey: .deviceTypeIdentifier)
    runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
    osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion)
    modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
    hardwareUDID = try container.decodeIfPresent(String.self, forKey: .hardwareUDID)
    isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? true
    isWireless = try container.decodeIfPresent(Bool.self, forKey: .isWireless) ?? false
    developerModeEnabled = try container.decodeIfPresent(
      Bool.self, forKey: .developerModeEnabled)
  }

  /// Ready to be acted on: a booted simulator, or a device the tooling can
  /// currently reach.
  public var isBooted: Bool {
    switch kind {
    case .simulator:
      return state.caseInsensitiveCompare("Booted") == .orderedSame
    case .physical:
      return isConnected
    }
  }

  public var capabilities: Set<DeviceCapability> {
    kind.capabilities
  }

  public func supports(_ capability: DeviceCapability) -> Bool {
    capabilities.contains(capability)
  }

  /// The platform and version, however the driving tool expressed it.
  public var runtimeName: String {
    if kind == .physical {
      guard let osVersion else { return modelName ?? "Unknown version" }
      return "iOS \(osVersion)"
    }
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

  /// Why this device cannot be acted on, or nil when it can.
  public var unreadyReason: String? {
    guard !isBooted else { return nil }
    switch kind {
    case .simulator:
      return "\(name) is shut down. Choose \u{201C}Boot / show simulator\u{201D} first."
    case .physical:
      return
        "\(name) is not connected. Plug it in or bring it onto the same network, and unlock it."
    }
  }
}

/// The name this type had when it only described simulators.
public typealias SimulatorDevice = Device

struct DeviceListResponse: Decodable {
  let devices: [String: [SimulatorDevice]]
}

public enum DeviceResolver {
  public static func resolve(
    selector: String?,
    devices: [Device],
    requireBooted: Bool
  ) throws -> Device {
    let available = devices.filter(\.isAvailable)

    guard let selector, !selector.isEmpty else {
      let ready = available.filter(\.isBooted)
      if ready.count == 1 { return ready[0] }
      if ready.isEmpty { throw SimctlBuddyError.noBootedDevice }
      throw SimctlBuddyError.ambiguousDevice(
        "ready",
        matches: ready.map { "\($0.name) [\($0.udid)]" }
      )
    }

    // Match without regard for readiness first, so a device that is simply not
    // connected says so instead of looking like a typo.
    let matches = matching(selector, in: available)
    if matches.count == 1, let reason = matches[0].unreadyReason, requireBooted {
      throw SimctlBuddyError.setupProblem(reason)
    }

    let candidates = requireBooted ? matches.filter(\.isBooted) : matches
    if candidates.count == 1 { return candidates[0] }
    if candidates.count > 1 {
      throw SimctlBuddyError.ambiguousDevice(
        selector,
        matches: candidates.map { "\($0.name) [\($0.kind.label) · \($0.runtimeName)]" }
      )
    }
    throw SimctlBuddyError.deviceNotFound(selector)
  }

  /// Exact identifier, then exact name, then a unique partial match.
  private static func matching(_ selector: String, in devices: [Device]) -> [Device] {
    if let exactUDID = devices.first(where: {
      $0.udid.caseInsensitiveCompare(selector) == .orderedSame
        || $0.hardwareUDID?.caseInsensitiveCompare(selector) == .orderedSame
    }) {
      return [exactUDID]
    }
    let exactNames = devices.filter { $0.name.caseInsensitiveCompare(selector) == .orderedSame }
    if !exactNames.isEmpty { return exactNames }
    return devices.filter {
      $0.name.localizedCaseInsensitiveContains(selector)
        || $0.udid.localizedCaseInsensitiveContains(selector)
    }
  }
}
