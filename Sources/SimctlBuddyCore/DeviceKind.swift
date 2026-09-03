import Foundation

/// Simulators are driven with `simctl`, physical devices with `devicectl`. The
/// two tools overlap but are not interchangeable, so the kind travels with the
/// device and decides which actions are even offered.
public enum DeviceKind: String, Codable, Equatable, Sendable, CaseIterable {
  case simulator
  case physical

  public var label: String {
    switch self {
    case .simulator: return "Simulator"
    case .physical: return "Device"
    }
  }

  /// The tool that drives it, for error messages.
  public var tool: String {
    switch self {
    case .simulator: return "simctl"
    case .physical: return "devicectl"
    }
  }
}

/// Something a device can be asked to do.
///
/// Physical devices cannot do everything a simulator can: there is no booting a
/// phone, no faked push, and no privacy database to poke. Listing the gaps here
/// means an action can be refused with an explanation, or hidden, instead of
/// failing with whatever the underlying tool happens to print.
public enum DeviceCapability: String, Equatable, Sendable, CaseIterable {
  case boot
  case shutdown
  case reboot
  case openURL
  case install
  case launch
  case terminate
  case listApps
  case runningApps
  case screenshot
  case record
  case clipboard
  case location
  case appearance
  case statusBar
  case push
  case privacy
  case firebaseInstall

  /// Why a device cannot do this, phrased for someone who just tried.
  public func unavailableReason(for kind: DeviceKind) -> String {
    switch (self, kind) {
    case (.boot, .physical), (.shutdown, .physical):
      return "A physical device has no boot state. Unlock it and it is ready."
    case (.push, .physical):
      return
        "Simulated push needs simctl. A real device has to receive a real notification through APNs."
    case (.privacy, .physical):
      return "devicectl cannot change privacy permissions. Reset them on the device in Settings."
    case (.firebaseInstall, .simulator):
      return
        "App Distribution only serves signed device builds, which a simulator cannot run. Install a simulator build with `simbuddy install`."
    case (.reboot, .simulator):
      return "Use shutdown and boot for a simulator."
    default:
      return "\(kind.tool) does not support this."
    }
  }
}

extension DeviceKind {
  /// Everything this kind of device can be asked to do.
  public var capabilities: Set<DeviceCapability> {
    switch self {
    case .simulator:
      return Set(DeviceCapability.allCases).subtracting([.reboot, .firebaseInstall])
    case .physical:
      // devicectl has no boot/shutdown, no simulated push, and no privacy
      // control. Recording exists (`capture screen-record`) but is not wired up
      // yet, so it is not offered rather than offered and failing.
      return Set(DeviceCapability.allCases)
        .subtracting([.boot, .shutdown, .push, .privacy, .record])
    }
  }
}
