import Foundation
import XCTest

@testable import SimctlBuddyCore

final class DeviceServiceTests: XCTestCase {
  private let simulator = Device(
    name: "iPhone 17 Pro", udid: "SIM-1", state: "Booted", isAvailable: true,
    kind: .simulator, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5")
  private let shutdownSimulator = Device(
    name: "iPhone 16", udid: "SIM-2", state: "Shutdown", isAvailable: true,
    kind: .simulator, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
  private let phone = Device(
    name: "Horvat iOS", udid: "DEV-1", state: "Connected", isAvailable: true,
    kind: .physical, osVersion: "27.0", modelName: "iPhone 16 Pro",
    hardwareUDID: "00008140-0011150C36D3001C", isConnected: true, isWireless: true)
  private let awayPhone = Device(
    name: "Katja's iPad", udid: "DEV-2", state: "Unavailable", isAvailable: true,
    kind: .physical, osVersion: "26.6.1", isConnected: false)

  private var all: [Device] { [simulator, shutdownSimulator, phone, awayPhone] }

  // MARK: - Resolution

  func testAnExactIdentifierWins() throws {
    XCTAssertEqual(
      try DeviceResolver.resolve(selector: "DEV-1", devices: all, requireBooted: true).name,
      "Horvat iOS")
  }

  func testAPhysicalDeviceIsFoundByItsHardwareUDIDToo() throws {
    XCTAssertEqual(
      try DeviceResolver.resolve(
        selector: "00008140-0011150C36D3001C", devices: all, requireBooted: true
      ).name,
      "Horvat iOS")
  }

  /// The message people actually hit: the device exists, it is just not there.
  func testADisconnectedDeviceSaysSoRatherThanLookingLikeATypo() {
    XCTAssertThrowsError(
      try DeviceResolver.resolve(selector: "Katja's iPad", devices: all, requireBooted: true)
    ) { error in
      guard case .setupProblem(let message) = error as? SimctlBuddyError else {
        return XCTFail("expected a setup problem, got \(error)")
      }
      XCTAssertTrue(message.contains("not connected"), message)
    }
  }

  func testAShutDownSimulatorStillSaysToBootIt() {
    XCTAssertThrowsError(
      try DeviceResolver.resolve(selector: "iPhone 16", devices: all, requireBooted: true)
    ) { error in
      guard case .setupProblem(let message) = error as? SimctlBuddyError else {
        return XCTFail("expected a setup problem, got \(error)")
      }
      XCTAssertTrue(message.contains("shut down"), message)
    }
  }

  func testAnUnreadyDeviceIsStillResolvableWhenReadinessIsNotRequired() throws {
    XCTAssertEqual(
      try DeviceResolver.resolve(selector: "iPhone 16", devices: all, requireBooted: false).udid,
      "SIM-2")
  }

  func testSeveralReadyDevicesAreAmbiguous() {
    XCTAssertThrowsError(
      try DeviceResolver.resolve(selector: nil, devices: all, requireBooted: true)
    ) { error in
      guard case .ambiguousDevice = error as? SimctlBuddyError else {
        return XCTFail("expected ambiguity, got \(error)")
      }
    }
  }

  func testASingleReadyDeviceNeedsNoSelector() throws {
    XCTAssertEqual(
      try DeviceResolver.resolve(
        selector: nil, devices: [simulator, shutdownSimulator], requireBooted: true
      ).udid,
      "SIM-1")
  }

  func testNothingReadyIsItsOwnMessage() {
    XCTAssertThrowsError(
      try DeviceResolver.resolve(
        selector: nil, devices: [shutdownSimulator, awayPhone], requireBooted: true)
    ) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .noBootedDevice)
    }
  }

  func testAmbiguityNamesTheKindSoTheChoiceIsPossible() {
    let twins = [
      simulator,
      Device(
        name: "iPhone 17 Pro", udid: "DEV-9", state: "Connected", isAvailable: true,
        kind: .physical, osVersion: "27.0", isConnected: true),
    ]
    XCTAssertThrowsError(
      try DeviceResolver.resolve(selector: "iPhone 17 Pro", devices: twins, requireBooted: true)
    ) { error in
      guard case .ambiguousDevice(_, let matches) = error as? SimctlBuddyError else {
        return XCTFail("expected ambiguity")
      }
      XCTAssertTrue(matches.contains { $0.contains("Simulator") })
      XCTAssertTrue(matches.contains { $0.contains("Device") })
    }
  }

  // MARK: - Capability gate

  func testTheGateRefusesWhatAKindCannotDo() {
    let service = DeviceService()
    XCTAssertThrowsError(try service.require(.push, on: phone)) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .unsupportedAction(.push, kind: .physical))
    }
    XCTAssertThrowsError(try service.require(.privacy, on: phone))
    XCTAssertThrowsError(try service.require(.boot, on: phone))
    XCTAssertNoThrow(try service.require(.install, on: phone))
    XCTAssertNoThrow(try service.require(.openURL, on: phone))
  }

  func testTheGateAlsoRefusesADeviceThatIsNotThere() {
    XCTAssertThrowsError(try DeviceService().require(.openURL, on: awayPhone)) { error in
      guard case .setupProblem = error as? SimctlBuddyError else {
        return XCTFail("expected a setup problem")
      }
    }
  }

  func testSimulatorsKeepEverythingTheyHad() {
    let service = DeviceService()
    for capability in DeviceCapability.allCases where capability != .reboot {
      XCTAssertNoThrow(
        try service.require(capability, on: simulator), "simulators lost \(capability)")
    }
  }

  // MARK: - Bundle platform

  func testASimulatorBuildIsRefusedOnADevice() {
    let bundle = AppBundle(
      path: "/builds/Debug-iphonesimulator/MyApp.app", platform: .simulator,
      hasProvisioningProfile: false)

    XCTAssertNoThrow(try bundle.checkInstallable(on: .simulator))
    XCTAssertThrowsError(try bundle.checkInstallable(on: .physical)) { error in
      guard case .wrongBuildForDevice(_, _, let hint) = error as? SimctlBuddyError else {
        return XCTFail("expected a build mismatch")
      }
      XCTAssertTrue(hint.contains("-iphoneos"), hint)
    }
  }

  func testADeviceBuildIsRefusedOnASimulator() {
    let bundle = AppBundle(
      path: "/builds/Debug-iphoneos/MyApp.app", platform: .device, hasProvisioningProfile: true)

    XCTAssertNoThrow(try bundle.checkInstallable(on: .physical))
    XCTAssertThrowsError(try bundle.checkInstallable(on: .simulator)) { error in
      guard case .wrongBuildForDevice(_, _, let hint) = error as? SimctlBuddyError else {
        return XCTFail("expected a build mismatch")
      }
      XCTAssertTrue(hint.contains("-iphonesimulator"), hint)
    }
  }

  func testAnUnreadableBundleIsAllowedThroughRatherThanGuessed() {
    // Nothing to go on, so let the real tool decide instead of refusing wrongly.
    let bundle = AppBundle(path: "/builds/MyApp.app", platform: .unknown, hasProvisioningProfile: false)
    XCTAssertNoThrow(try bundle.checkInstallable(on: .simulator))
    XCTAssertNoThrow(try bundle.checkInstallable(on: .physical))
  }

  func testAProfileMakesItADeviceBuildEvenWithoutThePlistSaying() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let bundle = directory.appendingPathComponent("MyApp.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("x".utf8).write(to: bundle.appendingPathComponent("embedded.mobileprovision"))

    let read = try AppBundle.read(at: bundle.path)

    XCTAssertEqual(read.platform, .device)
    XCTAssertTrue(read.hasProvisioningProfile)
    XCTAssertThrowsError(try read.checkInstallable(on: .simulator))
  }

  func testSomethingThatIsNotAnAppBundleIsRejected() {
    XCTAssertThrowsError(try AppBundle.read(at: "/nowhere/MyApp.app"))
    XCTAssertThrowsError(try AppBundle.read(at: "/tmp"))
  }
}
