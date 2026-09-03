import Foundation
import XCTest

@testable import SimctlBuddyCore

/// Parsing is pinned against JSON captured from a real `devicectl`, trimmed to
/// the fields SimctlBuddy reads.
final class DevicectlParsingTests: XCTestCase {
  private let deviceList = """
    {
      "info": { "outcome": "success" },
      "result": {
        "devices": [
          {
            "identifier": "0EC1F9B7-E70C-5C26-8307-9436F1DA2C5E",
            "connectionProperties": {
              "pairingState": "paired",
              "transportType": "localNetwork",
              "tunnelState": "connected"
            },
            "deviceProperties": {
              "bootState": "booted",
              "developerModeStatus": "enabled",
              "name": "Horvat iOS",
              "osVersionNumber": "27.0"
            },
            "hardwareProperties": {
              "deviceType": "iPhone",
              "marketingName": "iPhone 16 Pro",
              "platform": "iOS",
              "productType": "iPhone17,1",
              "reality": "physical",
              "udid": "00008140-0011150C36D3001C"
            }
          },
          {
            "identifier": "7517900A-EBB8-5280-98FF-09F2EE1F6CD1",
            "connectionProperties": { "pairingState": "paired", "tunnelState": "unavailable" },
            "deviceProperties": { "name": "Katja's iPad", "osVersionNumber": "26.6.1" },
            "hardwareProperties": {
              "deviceType": "iPad", "marketingName": "iPad Air",
              "reality": "physical", "udid": "00008103-000000000000"
            }
          },
          {
            "identifier": "9F91E53D-01D7-430C-9318-0F11CBBB3B45",
            "connectionProperties": { "pairingState": "paired", "tunnelState": "disconnected",
              "transportType": "sameMachine" },
            "deviceProperties": { "bootState": "shutdown", "name": "iPhone 15 Pro",
              "osVersionNumber": "26.5" },
            "hardwareProperties": { "deviceType": "iPhone", "reality": "simulated" }
          }
        ]
      }
    }
    """

  func testOnlyPhysicalDevicesAreReturned() throws {
    let devices = try DevicectlClient.parseDevices(Data(deviceList.utf8))
    // devicectl lists simulators too; taking them would show each one twice.
    XCTAssertEqual(devices.map(\.name), ["Horvat iOS", "Katja's iPad"])
    XCTAssertTrue(devices.allSatisfy { $0.kind == .physical })
  }

  func testAConnectedDeviceIsReadyToActOn() throws {
    let device = try DevicectlClient.parseDevices(Data(deviceList.utf8))[0]

    XCTAssertEqual(device.udid, "0EC1F9B7-E70C-5C26-8307-9436F1DA2C5E")
    XCTAssertEqual(device.hardwareUDID, "00008140-0011150C36D3001C")
    XCTAssertEqual(device.state, "Connected")
    XCTAssertTrue(device.isConnected)
    XCTAssertTrue(device.isBooted, "a reachable device is ready")
    XCTAssertNil(device.unreadyReason)
    XCTAssertTrue(device.isWireless)
    XCTAssertEqual(device.developerModeEnabled, true)
    XCTAssertEqual(device.runtimeName, "iOS 27.0")
    XCTAssertEqual(device.modelName, "iPhone 16 Pro")
  }

  func testAPairedButUnreachableDeviceIsNotReady() throws {
    let device = try DevicectlClient.parseDevices(Data(deviceList.utf8))[1]

    XCTAssertEqual(device.state, "Unavailable")
    XCTAssertFalse(device.isBooted)
    XCTAssertTrue(device.isAvailable, "still paired")
    XCTAssertEqual(
      device.unreadyReason,
      "Katja's iPad is not connected. Plug it in or bring it onto the same network, and unlock it."
    )
  }

  func testRubbishIsReportedRatherThanSilentlyEmpty() {
    XCTAssertThrowsError(try DevicectlClient.parseDevices(Data("{}".utf8)))
    XCTAssertThrowsError(try DevicectlClient.parseDevices(Data("not json".utf8)))
  }

  private let appList = """
    {
      "result": {
        "apps": [
          { "bundleIdentifier": "com.example.One", "name": "One", "version": "1.0",
            "builtByDeveloper": true,
            "url": "file:///private/var/containers/Bundle/Application/AAA/One.app/" },
          { "bundleIdentifier": "at.spar.mobile", "name": "SPAR", "version": "2.1",
            "url": "file:///private/var/containers/Bundle/Application/BBB/Spar.app/" },
          { "name": "no identifier" }
        ]
      }
    }
    """

  func testAppsAreParsedAndSorted() throws {
    let apps = try DevicectlClient.parseApps(Data(appList.utf8))
    XCTAssertEqual(apps.map(\.bundleIdentifier), ["at.spar.mobile", "com.example.One"])
    XCTAssertEqual(apps[1].name, "One")
    XCTAssertEqual(apps[1].version, "1.0")
    XCTAssertTrue(apps[1].builtByDeveloper)
  }

  private let processList = """
    {
      "result": {
        "deviceIdentifier": "0EC1F9B7",
        "runningProcesses": [
          { "processIdentifier": 37, "executable": "file:///System/Library/CoreServices/SpringBoard.app/SpringBoard" },
          { "processIdentifier": 918,
            "executable": "file:///private/var/containers/Bundle/Application/AAA/One.app/One" },
          { "processIdentifier": 12 }
        ]
      }
    }
    """

  func testProcessesAreParsed() throws {
    let processes = try DevicectlClient.parseProcesses(Data(processList.utf8))
    XCTAssertEqual(processes.count, 3)
    XCTAssertEqual(processes[1].processIdentifier, 918)
  }

  func testAProcessIsMatchedToTheAppWhoseBundleItLivesIn() throws {
    let apps = try DevicectlClient.parseApps(Data(appList.utf8))
    let processes = try DevicectlClient.parseProcesses(Data(processList.utf8))

    let running = DevicectlClient.match(processes: processes, to: apps)

    XCTAssertEqual(running.map(\.bundleIdentifier), ["com.example.One"])
    XCTAssertEqual(running[0].processIdentifier, 918)
  }

  func testAnAppWithNoRunningProcessIsNotReportedAsRunning() throws {
    let apps = try DevicectlClient.parseApps(Data(appList.utf8))
    let running = DevicectlClient.match(processes: [], to: apps)
    XCTAssertTrue(running.isEmpty)
  }

  func testTheLaunchedProcessIdentifierIsRead() {
    let launch = """
      { "result": { "process": { "processIdentifier": 1234 } } }
      """
    XCTAssertEqual(
      DevicectlClient.parseLaunchedProcessIdentifier(Data(launch.utf8)), 1234)
    XCTAssertNil(DevicectlClient.parseLaunchedProcessIdentifier(Data("{}".utf8)))
  }

  func testCapabilitiesDifferByKind() {
    XCTAssertTrue(DeviceKind.simulator.capabilities.contains(.push))
    XCTAssertTrue(DeviceKind.simulator.capabilities.contains(.boot))
    XCTAssertFalse(DeviceKind.simulator.capabilities.contains(.reboot))

    XCTAssertFalse(DeviceKind.physical.capabilities.contains(.push))
    XCTAssertFalse(DeviceKind.physical.capabilities.contains(.privacy))
    XCTAssertFalse(DeviceKind.physical.capabilities.contains(.boot))
    XCTAssertTrue(DeviceKind.physical.capabilities.contains(.install))
    XCTAssertTrue(DeviceKind.physical.capabilities.contains(.reboot))
  }

  func testRefusalsExplainThemselves() {
    XCTAssertTrue(
      DeviceCapability.push.unavailableReason(for: .physical).contains("APNs"))
    XCTAssertTrue(
      DeviceCapability.boot.unavailableReason(for: .physical).contains("no boot state"))
  }

  /// simctl's own JSON has no kind, so it must still decode as a simulator.
  func testSimctlJSONStillDecodes() throws {
    let json = """
      { "name": "iPhone 17 Pro", "udid": "AAAA", "state": "Booted", "isAvailable": true,
        "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" }
      """
    let device = try JSONDecoder().decode(Device.self, from: Data(json.utf8))

    XCTAssertEqual(device.kind, .simulator)
    XCTAssertTrue(device.isBooted)
    XCTAssertTrue(device.isConnected)
    XCTAssertNil(device.osVersion)
  }
}
