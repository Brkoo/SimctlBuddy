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
    version: "0.4.0",
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
      Bundles.self,
      Paths.self,
      Firebase.self,
      Screenshot.self,
      Record.self,
      Clipboard.self,
      Push.self,
      Location.self,
      Appearance.self,
      Privacy.self,
      StatusBar.self,
      Config.self,
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
    help: "Device name, partial name, or identifier. Defaults to the only ready device."
  )
  var device: String?

  @Flag(help: "Only consider simulators.")
  var simulatorsOnly = false

  @Flag(help: "Only consider physical devices.")
  var devicesOnly = false

  /// Physical devices are opt-in.
  ///
  /// With no `--device` and no kind flag, only simulators are considered, so
  /// plugging a phone in cannot silently make every command ambiguous — or
  /// worse, aim an install at hardware.
  var kinds: Set<DeviceKind> {
    if simulatorsOnly { return [.simulator] }
    if devicesOnly { return [.physical] }
    return device == nil ? [.simulator] : Set(DeviceKind.allCases)
  }

  func validate() throws {
    if simulatorsOnly && devicesOnly {
      throw ValidationError("Pass either --simulators-only or --devices-only, not both.")
    }
  }

  /// Resolves the target across both kinds.
  func resolve(
    _ service: DeviceService = DeviceService(),
    requireBooted: Bool = true
  ) throws -> Device {
    try service.resolveDevice(device, requireBooted: requireBooted, kinds: kinds)
  }
}

private func printSuccess(_ message: String) {
  print("✓ \(message)")
}

/// Progress for long-running commands. stderr is unbuffered, so this appears as
/// it happens even when stdout is being piped somewhere.
private func note(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

/// Options every command that opens a deep link shares.
struct LinkFillOptions: ParsableArguments {
  @Option(
    name: .customLong("app"),
    help: "Saved app to open the link on, by name or bundle identifier. Supplies $scheme."
  )
  var app: String?

  @Option(
    name: .customLong("set"),
    help: "Give a parameter a value, as name=value. Repeatable."
  )
  var assignments: [String] = []
}

/// Turns a template plus `--app` and `--set` into a URL, or explains what is
/// missing. Scripts get an error rather than a prompt, since there may be no one
/// there to answer.
///
/// `installed` is only consulted when several saved apps could open the link,
/// because it costs a call to the device.
private func resolveLink(
  name: String,
  url: String,
  options: LinkFillOptions,
  apps: [SavedApp],
  scopedApps: [String]? = nil,
  rememberedApp: String? = nil,
  installed: () throws -> [String] = { [] }
) throws -> (url: String, app: SavedApp?) {
  let template = LinkTemplate.parse(url)
  let values = try LinkResolver.parseAssignments(options.assignments)
  let link = SavedLink(name: name, url: url, apps: scopedApps)

  var chosen: SavedApp?
  if let selector = options.app {
    let app = try LinkResolver.app(matching: selector, in: apps)
    guard link.appliesTo(bundleIdentifier: app.bundleIdentifier) else {
      throw ValidationError(
        "\(app.name) is not one of the apps this link is for: "
          + (scopedApps ?? []).joined(separator: ", "))
    }
    chosen = app
  } else if template.requiresScheme {
    var candidates = LinkResolver.candidates(for: link, apps: apps)
    if candidates.count > 1 {
      // Prefer an app that is actually on the device: opening a market's link
      // on a simulator that does not have that market installed only fails.
      let present = Set(try installed().map { $0.lowercased() })
      let onDevice = candidates.filter { present.contains($0.bundleIdentifier.lowercased()) }
      if !onDevice.isEmpty { candidates = onDevice }
    }
    guard let single = LinkResolver.automaticChoice(from: candidates, remembered: rememberedApp)
    else {
      if candidates.isEmpty { throw SimctlBuddyError.noSchemeForLink(name) }
      throw ValidationError(
        "\(candidates.count) saved apps could open this link. Pass --app with one of: "
          + candidates.map(\.name).joined(separator: ", "))
    }
    chosen = single
  }

  if template.requiresScheme, let chosen, chosen.scheme == nil {
    throw SimctlBuddyError.appHasNoScheme(chosen.name)
  }

  let missing = template.unresolvedParameters(given: values)
  if !missing.isEmpty {
    throw ValidationError(
      "This link needs a value for "
        + missing.map { "$\($0.name)" }.joined(separator: ", ")
        + ". Pass "
        + missing.map { "--set \($0.name)=<value>" }.joined(separator: " "))
  }

  return (try template.render(scheme: chosen?.scheme, values: values), chosen)
}

struct Devices: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List available iOS Simulators."
  )

  @Flag(help: "Only show booted simulators and connected devices.")
  var booted = false

  @Flag(help: "Print machine-readable JSON.")
  var json = false

  @Flag(help: "Only show simulators.")
  var simulatorsOnly = false

  @Flag(help: "Only show physical devices.")
  var devicesOnly = false

  func run() throws {
    var kinds = Set(DeviceKind.allCases)
    if simulatorsOnly { kinds = [.simulator] }
    if devicesOnly { kinds = [.physical] }
    // Asking specifically for devices should report why none appeared.
    var devices = try DeviceService().devices(kinds: kinds, strict: devicesOnly)
    if booted { devices = devices.filter(\.isBooted) }

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(devices), as: UTF8.self))
      return
    }

    guard !devices.isEmpty else {
      print("No devices found.")
      return
    }

    let nameWidth = max(6, devices.map(\.name.count).max() ?? 6)
    let runtimeWidth = max(7, devices.map(\.runtimeName.count).max() ?? 7)
    print(
      "\("DEVICE".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  "
        + "\("RUNTIME".padding(toLength: runtimeWidth, withPad: " ", startingAt: 0))  KIND       "
        + "STATE        IDENTIFIER"
    )
    for device in devices {
      let marker = device.isBooted ? "●" : "○"
      let name = device.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
      let runtime = device.runtimeName.padding(toLength: runtimeWidth, withPad: " ", startingAt: 0)
      let kind = device.kind.label.padding(toLength: 9, withPad: " ", startingAt: 0)
      let state = device.state.padding(toLength: 12, withPad: " ", startingAt: 0)
      let wireless = device.isWireless ? " (wireless)" : ""
      print("\(name)  \(runtime)  \(kind)  \(marker) \(state) \(device.udid)\(wireless)")
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
    // Only simulators boot, so a phone must not be matched here by accident.
    if let device {
      let service = DeviceService()
      let target = try? service.resolveDevice(device, requireBooted: false)
      if let target, target.kind == .physical {
        throw SimctlBuddyError.unsupportedAction(.boot, kind: .physical)
      }
    }
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
      let service = DeviceService()
      let device = try target.resolve(service)
      try service.require(.shutdown, on: device)
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

  @Argument(help: "URL, or a template such as $scheme://profile/$id.")
  var url: String

  @OptionGroup var target: DeviceOption
  @OptionGroup var fill: LinkFillOptions

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    let resolved = try resolveLink(
      name: url,
      url: url,
      options: fill,
      apps: try AppStore().load(),
      installed: { try service.installedBundleIdentifiers(device: device) }
    )
    try service.openURL(resolved.url, device: device)
    printSuccess("Opened \(resolved.url) on \(device.name)")
  }
}

struct Links: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Save and run reusable deep links.",
    subcommands: [
      LinksList.self, LinksAdd.self, LinksRun.self, LinksRemove.self,
      LinksExport.self, LinksImport.self,
    ],
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
      let name = link.name.padding(toLength: width, withPad: " ", startingAt: 0)
      var notes = [String]()
      let template = link.template
      if template.requiresScheme { notes.append("$scheme") }
      let parameters = template.parameters
      if !parameters.isEmpty {
        notes.append(parameters.map { "$\($0.name)" }.joined(separator: " "))
      }
      if let apps = link.apps, !apps.isEmpty { notes.append(apps.joined(separator: " ")) }
      let suffix = notes.isEmpty ? "" : "   [\(notes.joined(separator: " · "))]"
      print("\(name)  \(link.url)\(suffix)")
    }
  }
}

struct LinksAdd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Save a named deep link.")

  @Argument(help: "Short memorable name.")
  var name: String

  @Argument(help: "Deep link URL, or a template. See `simbuddy links add --help`.")
  var url: String

  @Option(
    name: .customLong("app"),
    help: "Restrict this link to a saved app, by bundle identifier. Repeatable."
  )
  var apps: [String] = []

  @Flag(help: "Replace an existing link with the same name.")
  var force = false

  func run() throws {
    try LinkStore().add(name: name, url: url, apps: apps, force: force)
    let template = LinkTemplate.parse(url)
    printSuccess("Saved \(name) → \(url)")
    if template.requiresScheme {
      print("  $scheme is filled in from the app the link is opened on.")
    }
    for parameter in template.parameters {
      let suffix = parameter.defaultValue.map { " (default \($0))" } ?? ""
      print("  $\(parameter.name) is asked for when the link runs\(suffix)")
    }
    if !apps.isEmpty {
      print("  offered only for: \(apps.joined(separator: ", "))")
    }
  }
}

struct LinksRun: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "run", abstract: "Open a saved deep link.")

  @Argument(help: "Saved link name.")
  var name: String

  @OptionGroup var target: DeviceOption
  @OptionGroup var fill: LinkFillOptions

  func run() throws {
    let link = try LinkStore().link(named: name)
    let store = LinkValueStore()
    let service = DeviceService()
    let device = try target.resolve(service)

    let resolved = try resolveLink(
      name: link.name,
      url: link.url,
      options: fill,
      apps: try AppStore().load(),
      scopedApps: link.apps,
      // Only a hint: it still has to be an app this link applies to.
      rememberedApp: store.memory(for: link.name).app,
      installed: { try service.installedBundleIdentifiers(device: device) }
    )
    try service.openURL(resolved.url, device: device)
    try? store.remember(
      values: try LinkResolver.parseAssignments(fill.assignments),
      app: resolved.app?.bundleIdentifier,
      for: link.name
    )
    let via = resolved.app.map { " via \($0.name)" } ?? ""
    printSuccess("Opened \(name) → \(resolved.url)\(via) on \(device.name)")
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

struct LinksExport: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "export",
    abstract: "Write saved deep links to a file, or to stdout.",
    discussion: """
      The exported file has the same shape as links.json, so it can be checked
      into a repository and imported on another machine as-is.
      """
  )

  @Argument(help: "Output file. Omit to print to stdout.", completion: .file(extensions: ["json"]))
  var output: String?

  func run() throws {
    let store = LinkStore()
    guard let output else {
      print(String(decoding: try store.exportData(), as: UTF8.self), terminator: "")
      return
    }
    let path = try store.export(to: output)
    let count = try store.load().count
    printSuccess("Exported \(count) deep link\(count == 1 ? "" : "s") to \(path)")
  }
}

struct LinksImport: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "import",
    abstract: "Merge deep links from a file into the saved set."
  )

  @Argument(help: "File to read.", completion: .file(extensions: ["json"]))
  var input: String

  @Flag(help: "Overwrite saved links when the names collide.")
  var force = false

  @Flag(help: "Replace every saved link with the contents of the file.")
  var replaceAll = false

  @Flag(help: "Print what would change without writing anything.")
  var dryRun = false

  func validate() throws {
    if force && replaceAll {
      throw ValidationError("Pass either --force or --replace-all, not both.")
    }
  }

  func run() throws {
    let strategy: ImportStrategy =
      replaceAll ? .replaceAll : (force ? .replaceExisting : .skipExisting)
    let store = LinkStore()

    if dryRun {
      // Run the merge against a throwaway copy so nothing is written.
      let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("simbuddy-dry-\(UUID().uuidString).json")
      defer { try? FileManager.default.removeItem(at: scratch) }
      try store.exportData().write(to: scratch, options: .atomic)
      let summary = try LinkStore(fileURL: scratch)
        .importLinks(fromFileAt: input, strategy: strategy)
      report(summary, prefix: "Would import")
      return
    }

    let summary = try store.importLinks(fromFileAt: input, strategy: strategy)
    report(summary, prefix: "Imported")
  }

  private func report(_ summary: ImportSummary, prefix: String) {
    printSuccess("\(prefix): \(summary.headline)")
    for line in summary.details { print("  \(line)") }
    if !summary.skipped.isEmpty {
      print("Pass --force to overwrite links that already exist.")
    }
  }
}

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Install an .app bundle.",
    discussion: """
      Pass a path, or --saved to install a path remembered with `simbuddy paths
      add`. Every successful install is remembered, so `simbuddy paths list`
      shows what was installed recently.
      """
  )

  @Argument(help: "Path to a built .app bundle.", completion: .file(extensions: ["app"]))
  var app: String?

  @Option(name: .customLong("saved"), help: "Install a saved path by name instead.")
  var savedName: String?

  @Option(name: .customLong("save-as"), help: "Remember this path under a name after installing.")
  var saveAs: String?

  @OptionGroup var target: DeviceOption

  func validate() throws {
    if app == nil && savedName == nil {
      throw ValidationError("Pass a path to an .app bundle, or --saved <name>.")
    }
    if app != nil && savedName != nil {
      throw ValidationError("Pass either a path or --saved <name>, not both.")
    }
  }

  func run() throws {
    let store = PathStore()
    let requested = try savedName.map { try store.path(named: $0).path } ?? app ?? ""
    let service = DeviceService()
    let device = try target.resolve(service)
    let bundle = try service.install(appAt: requested, device: device)
    try? store.recordRecent(bundle.path)
    printSuccess("Installed \(bundle.name) on \(device.name)")
    if let saveAs {
      try store.add(name: saveAs, path: bundle.path, force: true)
      printSuccess("Saved path \(saveAs) \u{2192} \(bundle.path)")
    }
  }
}

struct Paths: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Save and reuse paths to built .app bundles.",
    subcommands: [PathsList.self, PathsAdd.self, PathsRemove.self, PathsForget.self],
    defaultSubcommand: PathsList.self
  )
}

struct PathsList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List saved and recently installed app paths.")

  @Flag(help: "Print machine-readable JSON.")
  var json = false

  func run() throws {
    let book = try PathStore().load()

    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      print(String(decoding: try encoder.encode(book), as: UTF8.self))
      return
    }

    guard !book.saved.isEmpty || !book.recent.isEmpty else {
      print("No app paths yet. Add one with `simbuddy paths add <name> <path-to.app>`.")
      return
    }

    if !book.saved.isEmpty {
      print("SAVED")
      let width = book.saved.map(\.name.count).max() ?? 0
      for saved in book.saved {
        let name = saved.name.padding(toLength: width, withPad: " ", startingAt: 0)
        let marker = saved.exists ? " " : "!"
        print("\(marker) \(name)  \(saved.path)")
      }
      if book.saved.contains(where: { !$0.exists }) {
        print("! marks a path that is not on disk right now.")
      }
    }
    if !book.recent.isEmpty {
      if !book.saved.isEmpty { print("") }
      print("RECENT")
      for path in book.recent { print("  \(path)") }
    }
  }
}

struct PathsAdd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Save a path to a built .app bundle under a name.")

  @Argument(help: "Short name to remember the build by.")
  var name: String

  @Argument(help: "Path to a .app bundle.", completion: .file(extensions: ["app"]))
  var path: String

  @Flag(help: "Replace an existing saved path with the same name.")
  var force = false

  func run() throws {
    try PathStore().add(name: name, path: path, force: force)
    printSuccess("Saved path \(name) \u{2192} \(try PathStore.validate(path))")
  }
}

struct PathsRemove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove a saved app path.")

  @Argument(help: "Saved path name.")
  var name: String

  func run() throws {
    try PathStore().remove(name: name)
    printSuccess("Removed saved path \(name)")
  }
}

struct PathsForget: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "forget-recent", abstract: "Clear the recently installed list.")

  func run() throws {
    try PathStore().clearRecents()
    printSuccess("Cleared recently installed paths")
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
    let service = DeviceService()
    let device = try target.resolve(service)
    let output = try service.launch(
      bundleIdentifier, device: device, arguments: arguments, restart: restart)
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.terminate(bundleIdentifier, device: device)
    printSuccess("Terminated \(bundleIdentifier) on \(device.name)")
  }
}

struct Apps: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect the apps on a simulator.",
    subcommands: [AppsList.self, AppsRunning.self],
    defaultSubcommand: AppsList.self
  )
}

struct AppsList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List installed apps as JSON.")

  @OptionGroup var target: DeviceOption

  @Flag(help: "Print only bundle identifiers, one per line.")
  var identifiers = false

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    // simctl's raw plist dump has no devicectl equivalent, so a physical device
    // gets the identifier list either way.
    if identifiers || device.kind == .physical {
      for identifier in try service.installedBundleIdentifiers(device: device) {
        print(identifier)
      }
      return
    }
    print(try service.simctl.simctl(["listapps", device.udid]))
  }
}

struct AppsRunning: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "running",
    abstract: "List the bundle identifiers of apps running right now."
  )

  @OptionGroup var target: DeviceOption

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    let running = try service.runningBundleIdentifiers(device: device)
    guard !running.isEmpty else {
      print("No apps are running on \(device.name).")
      return
    }
    for identifier in running { print(identifier) }
  }
}

struct Bundles: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Save and reuse app bundle identifiers.",
    subcommands: [BundlesList.self, BundlesAdd.self, BundlesRemove.self],
    defaultSubcommand: BundlesList.self
  )
}

struct BundlesList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "List saved app bundle identifiers.")

  func run() throws {
    let apps = try AppStore().load()
    guard !apps.isEmpty else {
      print("No saved apps yet. Add one with `simbuddy bundles add <name> <bundle-id>`.")
      return
    }
    let width = apps.map(\.name.count).max() ?? 0
    let identifierWidth = apps.map(\.bundleIdentifier.count).max() ?? 0
    for app in apps {
      let name = app.name.padding(toLength: width, withPad: " ", startingAt: 0)
      let identifier = app.bundleIdentifier
        .padding(toLength: identifierWidth, withPad: " ", startingAt: 0)
      let scheme = app.scheme.map { "  \($0)://" } ?? ""
      print("\(name)  \(identifier)\(scheme)")
    }
  }
}

struct BundlesAdd: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Save an app bundle identifier under a name.")

  @Argument(help: "Short name to remember the app by.")
  var name: String
  @Argument(help: "App bundle identifier.")
  var bundleIdentifier: String
  @Option(help: "The app's URL scheme, used to fill $scheme in deep links.")
  var scheme: String?
  @Flag(help: "Replace an existing saved app with the same name.")
  var force = false

  func run() throws {
    try AppStore().add(
      name: name, bundleIdentifier: bundleIdentifier, scheme: scheme, force: force)
    let suffix = scheme.map { "  (\($0)://)" } ?? ""
    printSuccess("Saved app \(name) → \(bundleIdentifier)\(suffix)")
  }
}

struct BundlesRemove: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove a saved app.")

  @Argument(help: "Saved app name.")
  var name: String

  func run() throws {
    try AppStore().remove(name: name)
    printSuccess("Removed saved app \(name)")
  }
}

/// Makes sure a capture has somewhere to land, in case a configured directory
/// was moved or deleted since it was set.
private func ensureParentDirectory(of path: String) throws {
  let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
  try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
}

struct Screenshot: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Capture a simulator screenshot.",
    discussion: """
      With no path, the file is named simbuddy-<timestamp>.png and written to the
      directory from `simbuddy config set screenshot-directory`, or to the
      working directory when that is not set.
      """
  )

  @Argument(help: "Output PNG path.", completion: .file(extensions: ["png"]))
  var output: String?

  @Option(help: "Directory to write into, overriding the configured one.", completion: .directory)
  var directory: String?

  @OptionGroup var target: DeviceOption

  func run() throws {
    let settings = try SettingsStore().load()
    let service = DeviceService()
    let device = try target.resolve(service)
    let absolute = settings.destination(
      explicit: output,
      directory: directory ?? settings.screenshotDirectory,
      fileName: CaptureName.screenshot()
    )
    try ensureParentDirectory(of: absolute)
    try service.screenshot(to: absolute, device: device)
    printSuccess("Saved screenshot to \(absolute)")
  }
}

extension Recorder.Codec: ExpressibleByArgument {}

struct Record: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Record the simulator screen to a movie.",
    discussion: """
      Recording runs until you press Ctrl+C, or until --duration elapses. With no
      path, the file is named simbuddy-<timestamp>.mov and written to the
      directory from `simbuddy config set recording-directory`, or to the working
      directory when that is not set.
      """
  )

  @Argument(help: "Output movie path.", completion: .file(extensions: ["mov", "mp4"]))
  var output: String?

  @Option(help: "Directory to write into, overriding the configured one.", completion: .directory)
  var directory: String?

  @Option(help: "Video codec: h264 or hevc.")
  var codec: Recorder.Codec = .h264

  @Option(help: "Stop automatically after this many seconds.")
  var duration: Double?

  @OptionGroup var target: DeviceOption

  func validate() throws {
    if let duration, duration <= 0 {
      throw ValidationError("--duration must be greater than zero.")
    }
  }

  func run() throws {
    let settings = try SettingsStore().load()
    let client = SimctlClient()
    let device = try client.resolveDevice(target.device)
    let absolute = settings.destination(
      explicit: output,
      directory: directory ?? settings.recordingDirectory,
      fileName: CaptureName.recording()
    )

    let recorder = Recorder()
    note("Starting the recorder…")
    let session = try recorder.start(device: device, path: absolute, codec: codec)
    printSuccess("Recording \(device.name) to \(session.path)")

    if let duration {
      print("Stopping after \(Self.format(duration)). Press Ctrl+C to stop sooner.")
    } else {
      print("Press Ctrl+C to stop.")
    }

    installInterruptHandler()
    let deadline = duration.map { Date().addingTimeInterval($0) }
    while !recordingShouldStop {
      if let deadline, Date() >= deadline { break }
      usleep(100_000)
    }

    // stdout is buffered when piped, so progress goes to stderr where it shows
    // up immediately and stays out of a captured recording path.
    note("Stopping and finalizing…")
    let finished = try recorder.stop()
    printSuccess(
      "Saved \(Self.format(finished.duration())) to \(finished.path)")
  }

  private func installInterruptHandler() {
    recordingShouldStop = false
    // A default SIGINT would kill this process and leave simctl finalizing
    // nothing, so take the signal and stop the recording properly.
    signal(SIGINT) { _ in recordingShouldStop = true }
    signal(SIGTERM) { _ in recordingShouldStop = true }
  }

  private static func format(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded())
    guard whole >= 60 else { return "\(whole)s" }
    return "\(whole / 60)m \(whole % 60)s"
  }
}

/// Signal handlers cannot capture context, so the stop flag lives here.
private nonisolated(unsafe) var recordingShouldStop = false

struct Config: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Read and change stored preferences.",
    subcommands: [ConfigList.self, ConfigGet.self, ConfigSet.self, ConfigUnset.self],
    defaultSubcommand: ConfigList.self
  )
}

extension SettingsKey: ExpressibleByArgument {}

struct ConfigList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list", abstract: "Show every setting and its value.")

  func run() throws {
    let store = SettingsStore()
    let settings = try store.load()
    let width = SettingsKey.allCases.map(\.rawValue.count).max() ?? 0
    for key in SettingsKey.allCases {
      let name = key.rawValue.padding(toLength: width, withPad: " ", startingAt: 0)
      let value: String
      switch key {
      case .screenshotDirectory:
        value = settings.screenshotDirectory ?? "(working directory)"
      case .recordingDirectory:
        value = settings.recordingDirectory ?? "(working directory)"
      case .firebaseServiceAccount:
        value = settings.firebaseServiceAccount ?? "(none)"
      }
      print("\(name)  \(value)")
    }
    print("")
    print("Stored in \(store.fileURL.path)")
  }
}

struct ConfigGet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get", abstract: "Print one setting.")

  @Argument(help: "Setting name, for example screenshot-directory.")
  var key: SettingsKey

  func run() throws {
    guard let value = try SettingsStore().value(for: key) else { return }
    print(value)
  }
}

struct ConfigSet: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Change one setting.",
    discussion: "Directories are created if they do not exist yet."
  )

  @Argument(help: "Setting name, for example screenshot-directory.")
  var key: SettingsKey

  @Argument(help: "New value.", completion: .directory)
  var value: String

  func run() throws {
    let resolved = try SettingsStore().set(key, to: value)
    printSuccess("Set \(key.rawValue) to \(resolved)")
  }
}

struct ConfigUnset: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "unset", abstract: "Return one setting to its default.")

  @Argument(help: "Setting name.")
  var key: SettingsKey

  func run() throws {
    try SettingsStore().clear(key)
    printSuccess("Cleared \(key.rawValue)")
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.copyToClipboard(text, device: device)
    printSuccess("Copied text to \(device.name)")
  }
}

struct ClipboardPaste: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "paste", abstract: "Print the simulator clipboard.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    print(try service.readClipboard(device: device))
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.require(.push, on: device)
    let client = service.simctl
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.setLocation(latitude: latitude, longitude: longitude, device: device)
    printSuccess("Set \(device.name) location to \(latitude),\(longitude)")
  }
}

struct LocationClear: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear", abstract: "Stop location simulation.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.clearLocation(device: device)
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.setAppearance(appearance.rawValue, device: device)
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
    // `service` here is the privacy service being reset, so the device service
    // needs its own name.
    let devices = DeviceService()
    let device = try target.resolve(devices)
    try devices.require(.privacy, on: device)
    let client = devices.simctl
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
  let deviceService = DeviceService()
  let device = try target.resolve(deviceService)
  try deviceService.require(.privacy, on: device)
  let client = deviceService.simctl
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
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.applyCleanStatusBar(device: device)
    printSuccess("Applied a clean status bar to \(device.name)")
  }
}

struct StatusBarClear: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clear", abstract: "Clear all status-bar overrides.")

  @OptionGroup var target: DeviceOption

  func run() throws {
    let service = DeviceService()
    let device = try target.resolve(service)
    try service.clearStatusBar(device: device)
    printSuccess("Cleared status-bar overrides on \(device.name)")
  }
}

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the local Xcode and Simulator setup.")

  func run() throws {
    for line in try DeviceService().diagnostics() {
      printSuccess(line)
    }
  }
}

// MARK: - Firebase App Distribution

struct Firebase: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Install builds from Firebase App Distribution.",
    discussion: """
      App Distribution serves signed iOS binaries, so these builds install on a
      connected device rather than a simulator.

      Save an app once with `simbuddy firebase save <name> <appId>`, then list
      and install its builds by that name. A credential is found automatically
      from a service account key, gcloud, or the Firebase CLI — run
      `simbuddy firebase status` to see which.
      """,
    subcommands: [
      FirebaseStatus.self,
      FirebaseProjects.self,
      FirebaseApps.self,
      FirebaseSave.self,
      FirebaseForget.self,
      FirebaseReleases.self,
      FirebaseInstall.self,
      FirebaseClean.self,
    ],
    defaultSubcommand: FirebaseReleases.self
  )
}

struct FirebaseStatus: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "status",
    abstract: "Show which Google credential will be used."
  )

  func run() throws {
    let credentials = FirebaseCredentials()
    let sources = credentials.availableSources()
    if sources.isEmpty {
      print("No credential source found on this machine.")
    } else {
      print("Credential sources found:")
      for source in sources { print("  • \(source)") }
    }
    print("")
    do {
      let token = try credentials.token()
      printSuccess("Signed in through \(token.source.label)")
      if token.needsQuotaProject {
        print("  A user credential, so requests name the project for quota.")
      }
    } catch {
      print("✗ \(error.localizedDescription)")
      throw ExitCode.failure
    }
  }
}

struct FirebaseProjects: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "projects",
    abstract: "List the Firebase projects you can see."
  )

  func run() throws {
    let projects = try FirebaseDistribution().projects()
    guard !projects.isEmpty else {
      print("No Firebase projects visible to this credential.")
      return
    }
    let width = projects.map(\.id.count).max() ?? 0
    for project in projects {
      print("\(project.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(project.name)")
    }
  }
}

struct FirebaseApps: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "List saved apps, or the iOS apps in your Firebase projects.",
    discussion: """
      With no options, lists the apps you have saved. Pass --all to walk every
      project you can see, or --project to look at one.

      An app ID looks like 1:1234567890:ios:abc123 and lives in the Firebase
      console under Project settings › General › Your apps, as "App ID".
      """
  )

  @Option(help: "List the iOS apps in this Firebase project.")
  var project: String?

  @Flag(help: "List the iOS apps in every project you can see.")
  var all = false

  func validate() throws {
    if all && project != nil {
      throw ValidationError("Pass either --all or --project, not both.")
    }
  }

  func run() throws {
    if all {
      try listEverything()
      return
    }
    if let project {
      printApps(try FirebaseDistribution().apps(projectID: project), in: project)
      return
    }

    let saved = try FirebaseStore().load()
    guard !saved.isEmpty else {
      print("No saved Firebase apps.")
      print("")
      print("Find an app ID with `simbuddy firebase apps --all`, then save it:")
      print("  simbuddy firebase save <name> <appId>")
      return
    }
    let width = saved.map(\.name.count).max() ?? 0
    for app in saved {
      print("\(app.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(app.appID)")
    }
  }

  private func printApps(_ apps: [FirebaseApp], in project: String) {
    guard !apps.isEmpty else {
      print("No iOS apps in \(project).")
      return
    }
    let width = apps.map(\.displayName.count).max() ?? 0
    for app in apps {
      print("\(app.displayName.padding(toLength: width, withPad: " ", startingAt: 0))  \(app.appID)")
    }
  }

  /// Access is granted per project, so some refusing is normal rather than a
  /// failure. They are listed at the end instead of interrupting the walk.
  private func listEverything() throws {
    note("Reading every project\u{2026}")
    let listings = try FirebaseDistribution().allApps()
    let found = listings.filter { !$0.apps.isEmpty }
    let width = found.flatMap(\.apps).map(\.displayName.count).max() ?? 0

    for listing in found {
      print("\(listing.projectID)")
      for app in listing.apps {
        let name = app.displayName.padding(toLength: width, withPad: " ", startingAt: 0)
        print("    \(name)  \(app.appID)")
      }
    }

    let empty = listings.filter { $0.apps.isEmpty && $0.isReadable }
    if !empty.isEmpty {
      print("")
      print("No iOS apps: \(empty.map(\.projectID).joined(separator: ", "))")
    }
    let refused = listings.filter { !$0.isReadable }
    if !refused.isEmpty {
      print("")
      print("Not readable with this credential: \(refused.map(\.projectID).joined(separator: ", "))")
      print("Those need the Firebase App Distribution Viewer role on the project.")
    }
    if found.isEmpty && refused.count == listings.count {
      throw ExitCode.failure
    }
  }
}

struct FirebaseSave: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "save",
    abstract: "Remember a Firebase app ID under a name.",
    discussion: """
      The app ID looks like 1:1234567890:ios:abc123. Find it either with
      `simbuddy firebase apps --all`, or in the Firebase console under
      Project settings › General › Your apps, where it is labelled "App ID".
      """
  )

  @Argument(help: "The name to use from now on.")
  var name: String

  @Argument(help: "The app ID, shaped 1:1234567890:ios:abc123.")
  var appID: String

  @Flag(help: "Replace a saved app with the same name.")
  var force = false

  func run() throws {
    try FirebaseStore().add(name: name, appID: appID, force: force)
    printSuccess("Saved Firebase app \(name) \u{2192} \(appID)")
  }
}

struct FirebaseForget: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "forget",
    abstract: "Remove a saved Firebase app."
  )

  @Argument(help: "The saved name to remove.")
  var name: String

  func run() throws {
    try FirebaseStore().remove(name: name)
    printSuccess("Removed \(name)")
  }
}

struct FirebaseReleases: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "releases",
    abstract: "List the builds available for an app."
  )

  @Argument(help: "A saved app name, or an app ID.")
  var app: String

  @Option(help: "How many builds to list.")
  var limit = 25

  @Option(help: "An App Distribution filter, for example 'displayVersion=\"1.2.0\"'.")
  var filter: String?

  @Flag(help: "Print the whole release notes instead of a one-line summary.")
  var notes = false

  func run() throws {
    let releases = try FirebaseDistribution().releases(app: app, limit: limit, filter: filter)
    guard !releases.isEmpty else {
      print("No builds found for \(app).")
      return
    }
    let width = releases.map(\.versionLabel.count).max() ?? 0
    for release in releases {
      let version = release.versionLabel.padding(toLength: width, withPad: " ", startingAt: 0)
      var line = "\(version)  \(release.releaseID)"
      if let created = release.createTime {
        line += "  \(RelativeDate.string(from: created))"
      }
      print(line)
      // CI often writes a whole commit log here, which buries the list.
      if notes {
        let full = release.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for line in full.split(separator: "\n") { print("    \(line)") }
      } else if let summary = release.summaryLine {
        print("    \(summary)")
      }
    }
  }
}

struct FirebaseInstall: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Download a build and install it on a connected device.",
    discussion: """
      Installs the newest build unless a release ID is given. The build is
      checked against the device's UDID before installing, because an ad hoc
      build only runs on devices that were registered when it was built.
      """
  )

  @Argument(help: "A saved app name, or an app ID.")
  var app: String

  @Argument(help: "A release ID from `firebase releases`. Defaults to the newest build.")
  var release: String?

  @Flag(help: "Install even when the build is not signed for this device.")
  var force = false

  @Flag(help: "Launch the app once it is installed.")
  var launch = false

  @OptionGroup var target: DeviceOption

  func validate() throws {
    if target.simulatorsOnly {
      throw ValidationError(
        SimctlBuddyError.firebaseNeedsPhysicalDevice.localizedDescription)
    }
  }

  func run() throws {
    let store = FirebaseStore()
    let appID = try store.resolve(app)
    let service = DeviceService()
    let distribution = FirebaseDistribution(service: service, store: store)

    // A device build needs a device, so physical devices are not opt-in here
    // the way they are elsewhere.
    let device: Device
    do {
      device = try service.resolveDevice(
        target.device, requireBooted: true, kinds: [.physical])
    } catch SimctlBuddyError.noBootedDevice, SimctlBuddyError.deviceNotFound {
      // The generic message talks about booting a simulator, which is not the
      // problem when the command only ever targets hardware.
      throw SimctlBuddyError.setupProblem(
        "No connected device. Plug one in, unlock it, and make sure Developer Mode is on — `simbuddy doctor` checks all three."
      )
    }

    note("Reading builds…")
    let releases = try distribution.releases(app: app, limit: 100)
    guard !releases.isEmpty else {
      throw SimctlBuddyError.releaseHasNoBinary(app)
    }

    let chosen: FirebaseRelease
    if let release {
      guard let match = releases.first(where: { $0.releaseID == release }) else {
        throw ValidationError(
          "No build with release ID \(release). Run `simbuddy firebase releases \(app)`.")
      }
      chosen = match
    } else {
      chosen = releases[0]
    }

    note("Fetching \(chosen.versionLabel)…")
    let report = try distribution.install(
      chosen, appID: appID, on: device, force: force)

    printSuccess("Installed \(chosen.versionLabel) on \(device.name)")
    for note in report.notes { print("  \(note)") }

    if launch, let identifier = report.bundle.bundleIdentifier {
      _ = try service.launch(identifier, device: device)
      printSuccess("Launched \(identifier)")
    }
  }
}

struct FirebaseClean: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean",
    abstract: "Delete downloaded builds."
  )

  func run() throws {
    let freed = try AppArchive.clearCache()
    let formatter = ByteCountFormatter()
    printSuccess("Freed \(formatter.string(fromByteCount: Int64(freed)))")
  }
}

/// Turns a timestamp into something readable in a list.
enum RelativeDate {
  static func string(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}
