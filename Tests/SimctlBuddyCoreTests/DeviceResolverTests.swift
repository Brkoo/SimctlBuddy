import XCTest

@testable import SimctlBuddyCore

final class DeviceResolverTests: XCTestCase {
  private let devices = [
    SimulatorDevice(
      name: "iPhone 17 Pro",
      udid: "AAAA-BBBB",
      state: "Booted",
      isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    ),
    SimulatorDevice(
      name: "iPhone 17",
      udid: "CCCC-DDDD",
      state: "Shutdown",
      isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    ),
    SimulatorDevice(
      name: "iPad Pro 13-inch",
      udid: "EEEE-FFFF",
      state: "Shutdown",
      isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
    ),
  ]

  func testDefaultsToOnlyBootedDevice() throws {
    let device = try DeviceResolver.resolve(
      selector: nil,
      devices: devices,
      requireBooted: true
    )
    XCTAssertEqual(device.udid, "AAAA-BBBB")
  }

  func testMatchesCaseInsensitiveFullName() throws {
    let device = try DeviceResolver.resolve(
      selector: "iphone 17",
      devices: devices,
      requireBooted: false
    )
    XCTAssertEqual(device.udid, "CCCC-DDDD")
  }

  func testMatchesPartialName() throws {
    let device = try DeviceResolver.resolve(
      selector: "ipad pro",
      devices: devices,
      requireBooted: false
    )
    XCTAssertEqual(device.udid, "EEEE-FFFF")
  }

  func testRejectsAmbiguousPartialName() {
    XCTAssertThrowsError(
      try DeviceResolver.resolve(
        selector: "iphone",
        devices: devices,
        requireBooted: false
      )
    ) { error in
      guard case SimctlBuddyError.ambiguousDevice(let selector, let matches) = error else {
        return XCTFail("Expected ambiguousDevice, got \(error)")
      }
      XCTAssertEqual(selector, "iphone")
      XCTAssertEqual(matches.count, 2)
    }
  }

  func testRejectsMissingBootedDevice() {
    let shutdown = devices.map {
      SimulatorDevice(
        name: $0.name,
        udid: $0.udid,
        state: "Shutdown",
        isAvailable: $0.isAvailable,
        runtimeIdentifier: $0.runtimeIdentifier
      )
    }
    XCTAssertThrowsError(
      try DeviceResolver.resolve(
        selector: nil,
        devices: shutdown,
        requireBooted: true
      )
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .noBootedDevice)
    }
  }

  func testFormatsRuntimeVersion() {
    XCTAssertEqual(devices[0].runtimeName, "iOS 26.0")
  }
}
