import ArgumentParser
import Foundation
import SimctlBuddyCore
import SimctlBuddyTUI

@main
struct SimctlBuddy: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "simbuddy",
    abstract: "A keyboard-driven terminal control deck for iOS Simulator.",
    discussion: """
      Run without arguments for the interactive terminal UI. Scriptable commands
      and reusable deep-link aliases are also available.
      """,
    version: "0.2.2",
    subcommands: [
      Interactive.self,
      Devices.self,
      Boot.self,
      Shutdown.self,
      Open.self,
      Links.self,
      Install.self,
      Launch.self,
      Terminate.self,
      Apps.self,
      Screenshot.self,
      Clipboard.self,
      Push.self,
      Location.self,
      Appearance.self,
      Privacy.self,
      StatusBar.self,
      Doctor.self,
    ],
    defaultSubcommand: Interactive.self
  )
}

struct Interactive: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tui",
    abstract: "Open the interactive terminal interface."
  )

  func run() throws {
    try SimulatorTUI().run()
  }
}

struct DeviceOption: ParsableArguments {
  @Option(
    name: [.short, .long],
    help: "Simulator name, partial name, or UDID. Defaults to the only booted simulator."
  )
  var device: String?
}

private func printSuccess(_ message: String) {
  print("✓ \(message)")
}

struct Devices: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List available iOS Simulators."
  )

  @Flag(help: "Only show booted simulators.")
  var booted = false

  @Flag(help: "Print machine-readable JSON.")
  var json = false

  func run() throws {
    var devices = try SimctlClient().devices()
    if booted { devices = devices.filter(\.isBooted) }

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(devices), as: UTF8.self))
      return
    }

    guard !devices.isEmpty else {
      print("No available iOS Simulators found.")
      return
    }

    let nameWidth = max(6, devices.map(\.name.count).max() ?? 6)
    let runtimeWidth = max(7, devices.map(\.runtimeName.count).max() ?? 7)
    print(
      "\("DEVICE".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  "
        + "\("RUNTIME".padding(toLength: runtimeWidth, withPad: " ", startingAt: 0))  STATE     UDID"
    )
    for device in devices {
      let marker = device.isBooted ? "●" : "○"
      let name = device.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
      let runtime = device.runtimeName.padding(toLength: runtimeWidth, withPad: " ", startingAt: 0)
      print(
        "\(name)  \(runtime)  \(marker) \(device.state.padding(toLength: 8, withPad: " ", startingAt: 0)) \(device.udid)"
      )
    }
  }
}

struct Boot: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Boot a simulator and open Simulator.app."
  )

  @Argument(help: "Simulator name, partial name, or UDID. Defaults to a booted or recent iPhone.")
  var device: String?

  @Flag(help: "Boot without opening Simulator.app.")
  var headless = false

  func run() throws {
    let simulator = try SimctlClient().boot(selector: device, openSimulator: !headless)
    printSuccess("\(simulator.name) is ready [\(simulator.udid)]")
  }
}

struct Shutdown: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Shut down a simulator.")

  @OptionGroup var target: DeviceOption

  @Flag(help: "Shut down every booted simulator.")
  var all = false

  func run() throws {
    let client = SimctlClient()
    if all {
      _ = try client.simctl(["shutdown", "all"])
      printSuccess("Shut down all simulators")
    } else {
      let device = try client.resolveDevice(target.device)
      _ = try client.simctl(["shutdown", device.udid])
      printSuccess("Shut down \(device.name)")
    }
  }
}

struct Open: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "open",
    abstract: "Open a universal link or custom URL scheme."
  )

  @Argument(help: "URL such as myapp://profile/42 or https://example.com/path.")
  var url: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    try client.openURL(url, device: device)
    printSuccess("Opened \(url) on \(device.name)")
  }
}

struct Links: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Save and run reusable deep links.",
    subcommands: [LinksList.self, LinksAdd.self, LinksRun.self, LinksRemove.self],
    defaultSubcommand: LinksList.self
  )
}

struct LinksList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List saved deep links.")

  func run() throws {
    let links = try LinkStore().load()
    guard !links.isEmpty else {
      print("No links saved. Add one with `simbuddy links add login myapp://login`.")
      return
    }
    let width = links.map(\.name.count).max() ?? 0
    for link in links {
      print("\(link.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(link.url)")
    }
  }
}

struct LinksAdd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Save a named deep link.")

  @Argument(help: "Short memorable name.")
  var name: String

  @Argument(help: "Deep link URL.")
  var url: String

  @Flag(help: "Replace an existing link with the same name.")
  var force = false

  func run() throws {
    try LinkStore().add(name: name, url: url, force: force)
    printSuccess("Saved \(name) → \(url)")
  }
}

struct LinksRun: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run", abstract: "Open a saved deep link.")

  @Argument(help: "Saved link name.")
  var name: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let link = try LinkStore().link(named: name)
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    try client.openURL(link.url, device: device)
    printSuccess("Opened \(name) → \(link.url) on \(device.name)")
  }
}

struct LinksRemove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove a saved deep link.")

  @Argument(help: "Saved link name.")
  var name: String

  func run() throws {
    try LinkStore().remove(name: name)
    printSuccess("Removed \(name)")
  }
}

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Install an .app bundle.")

  @Argument(help: "Path to a built .app bundle.", completion: .file(extensions: ["app"]))
  var app: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    let path = try client.validateAppBundle(at: app)
    _ = try client.simctl(["install", device.udid, path])
    printSuccess("Installed \(URL(fileURLWithPath: path).lastPathComponent) on \(device.name)")
  }
}

struct Launch: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Launch an installed app by bundle identifier.")

  @Argument(help: "App bundle identifier, for example com.example.app.")
  var bundleIdentifier: String

  @OptionGroup var target: DeviceOption

  @Flag(help: "Terminate the app before launching it.")
  var restart = false

  @Argument(parsing: .captureForPassthrough, help: "Arguments forwarded to the app.")
  var arguments: [String] = []

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    if restart {
      _ = try? client.simctl(["terminate", device.udid, bundleIdentifier])
    }
    let output = try client.simctl(["launch", device.udid, bundleIdentifier] + arguments)
    printSuccess(
      "Launched \(bundleIdentifier) on \(device.name)\(output.isEmpty ? "" : " (\(output))")")
  }
}

struct Terminate: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Terminate a running app.")

  @Argument(help: "App bundle identifier.")
  var bundleIdentifier: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["terminate", device.udid, bundleIdentifier])
    printSuccess("Terminated \(bundleIdentifier) on \(device.name)")
  }
}

struct Apps: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "List installed apps as JSON.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    print(try client.simctl(["listapps", device.udid]))
  }
}

struct Screenshot: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Capture a simulator screenshot.")

  @Argument(help: "Output PNG path. Defaults to ./screenshot-<timestamp>.png.")
  var output: String?

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    let path = output ?? "screenshot-\(Self.timestamp()).png"
    let absolute = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
      .standardizedFileURL.path
    _ = try client.simctl(["io", device.udid, "screenshot", absolute])
    printSuccess("Saved screenshot to \(absolute)")
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }
}

struct Clipboard: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Copy to or paste from the simulator clipboard.",
    subcommands: [ClipboardCopy.self, ClipboardPaste.self]
  )
}

struct ClipboardCopy: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "copy", abstract: "Copy text into the simulator.")

  @Argument(help: "Text to place on the simulator clipboard.")
  var text: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["pbcopy", device.udid], standardInput: Data(text.utf8))
    printSuccess("Copied text to \(device.name)")
  }
}

struct ClipboardPaste: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "paste", abstract: "Print the simulator clipboard.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    print(try client.simctl(["pbpaste", device.udid]))
  }
}

struct Push: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Send a simulated push notification.")

  @Argument(help: "App bundle identifier.")
  var bundleIdentifier: String

  @Argument(help: "Path to an APNs JSON payload.", completion: .file(extensions: ["apns", "json"]))
  var payload: String

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    let path = URL(fileURLWithPath: NSString(string: payload).expandingTildeInPath)
      .standardizedFileURL.path
    guard FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("No payload exists at \(path).")
    }
    _ = try client.simctl(["push", device.udid, bundleIdentifier, path])
    printSuccess("Sent push notification to \(bundleIdentifier)")
  }
}

struct Location: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Set or clear the simulated location.",
    subcommands: [LocationSet.self, LocationClear.self]
  )
}

struct LocationSet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Set a latitude and longitude.")

  @Argument var latitude: Double
  @Argument var longitude: Double
  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    try client.validateCoordinate(latitude: latitude, longitude: longitude)
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["location", device.udid, "set", "\(latitude),\(longitude)"])
    printSuccess("Set \(device.name) location to \(latitude),\(longitude)")
  }
}

struct LocationClear: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear", abstract: "Stop location simulation.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["location", device.udid, "clear"])
    printSuccess("Cleared simulated location on \(device.name)")
  }
}

struct Appearance: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Switch light or dark appearance.")

  enum Value: String, ExpressibleByArgument {
    case light
    case dark
  }

  @Argument var appearance: Value
  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["ui", device.udid, "appearance", appearance.rawValue])
    printSuccess("Set \(device.name) to \(appearance.rawValue) appearance")
  }
}

struct Privacy: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Grant, revoke, or reset app privacy permissions.",
    subcommands: [PrivacyGrant.self, PrivacyRevoke.self, PrivacyReset.self]
  )
}

struct PrivacyGrant: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "grant", abstract: "Grant a privacy service.")

  @Argument(help: "Service such as camera, microphone, photos, contacts, or location.")
  var service: String
  @Argument(help: "App bundle identifier.")
  var bundleIdentifier: String
  @OptionGroup var target: DeviceOption

  func run() throws {
    try changePrivacy("grant", service: service, bundleIdentifier: bundleIdentifier, target: target)
  }
}

struct PrivacyRevoke: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "revoke", abstract: "Revoke a privacy service.")

  @Argument var service: String
  @Argument var bundleIdentifier: String
  @OptionGroup var target: DeviceOption

  func run() throws {
    try changePrivacy(
      "revoke", service: service, bundleIdentifier: bundleIdentifier, target: target)
  }
}

struct PrivacyReset: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Reset privacy permissions.")

  @Option(help: "Optional service. Omit to reset every service for the app.")
  var service: String?
  @Argument(help: "App bundle identifier.")
  var bundleIdentifier: String
  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    var arguments = ["privacy", device.udid, "reset"]
    if let service { arguments.append(service) }
    arguments.append(bundleIdentifier)
    _ = try client.simctl(arguments)
    printSuccess("Reset privacy permissions for \(bundleIdentifier)")
  }
}

private func changePrivacy(
  _ action: String,
  service: String,
  bundleIdentifier: String,
  target: DeviceOption
) throws {
  let client = SimctlClient()
  let device = try client.resolveDevice(target.device)
  _ = try client.simctl(["privacy", device.udid, action, service, bundleIdentifier])
  let verb = action == "grant" ? "Granted" : "Revoked"
  printSuccess("\(verb) \(service) for \(bundleIdentifier)")
}

struct StatusBar: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "statusbar",
    abstract: "Create or clear a clean status bar for screenshots.",
    subcommands: [StatusBarClean.self, StatusBarClear.self]
  )
}

struct StatusBarClean: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean", abstract: "Set 9:41, full signal, and full battery.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl([
      "status_bar", device.udid, "override",
      "--time", "9:41",
      "--batteryState", "charged",
      "--batteryLevel", "100",
      "--wifiBars", "3",
      "--cellularBars", "4",
    ])
    printSuccess("Applied a clean status bar to \(device.name)")
  }
}

struct StatusBarClear: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear", abstract: "Clear all status-bar overrides.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    _ = try client.simctl(["status_bar", device.udid, "clear"])
    printSuccess("Cleared status-bar overrides on \(device.name)")
  }
}

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the local Xcode and Simulator setup.")

  func run() throws {
    let runner = ProcessRunner()
    let developerDir = try runner.run(executable: "/usr/bin/xcode-select", arguments: ["-p"])
    guard developerDir.exitCode == 0 else {
      throw ValidationError(
        "Xcode command-line tools are not selected. Run `sudo xcode-select -s /Applications/Xcode.app`."
      )
    }
    printSuccess(
      "Developer directory: \(developerDir.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
    )

    let version = try runner.run(executable: "/usr/bin/xcrun", arguments: ["simctl", "help"])
    guard version.exitCode == 0 else {
      throw ValidationError(
        "xcrun could not start simctl. Open Xcode once and finish installing components.")
    }
    printSuccess("simctl is available")

    let devices = try SimctlClient().devices()
    printSuccess("Found \(devices.count) available simulator\(devices.count == 1 ? "" : "s")")
    if let booted = devices.first(where: \.isBooted) {
      printSuccess("Booted: \(booted.name) [\(booted.runtimeName)]")
    } else {
      print("• No simulator is currently booted")
    }
  }
}
