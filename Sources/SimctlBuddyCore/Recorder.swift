import Foundation

/// Screen recording, which unlike every other simctl call has a lifetime:
/// `simctl io recordVideo` runs until it receives SIGINT and only then
/// finalizes the movie. This owns that process so both the interface and the
/// command line can start a recording, keep working, and stop it later.
public final class Recorder: @unchecked Sendable {
  public struct Session: Equatable, Sendable {
    public let deviceUDID: String
    public let deviceName: String
    public let path: String
    public let startedAt: Date

    public init(deviceUDID: String, deviceName: String, path: String, startedAt: Date) {
      self.deviceUDID = deviceUDID
      self.deviceName = deviceName
      self.path = path
      self.startedAt = startedAt
    }

    public var fileName: String {
      URL(fileURLWithPath: path).lastPathComponent
    }

    public func duration(at date: Date = Date()) -> TimeInterval {
      max(0, date.timeIntervalSince(startedAt))
    }
  }

  public enum Codec: String, CaseIterable, Sendable {
    /// Plays anywhere, which matters more than file size for a bug report.
    case h264
    case hevc
  }

  /// simctl announces itself on stderr once the first frame lands. Waiting for
  /// that turns "probably recording" into "recording".
  private static let startupTimeout: TimeInterval = 6
  /// Finalizing a long movie takes a moment; abandoning it early would leave a
  /// truncated file.
  private static let shutdownTimeout: TimeInterval = 30
  /// How long to wait after escalating from SIGINT to SIGTERM and SIGKILL.
  private static let escalationTimeout: TimeInterval = 5

  /// The command that performs a recording. Overridable so the start and stop
  /// lifecycle can be tested without a booted simulator.
  struct Launch: Sendable {
    let path: String
    let arguments: [String]
  }

  private let lock = NSLock()
  private let xcrunPath: String
  private let makeLaunch: (@Sendable (SimulatorDevice, String, Codec) -> Launch)?
  private var process: Process?
  private var currentSession: Session?
  private var scratchDirectory: URL?
  private var resolvedSimctlPath: String?

  public init(xcrunPath: String = "/usr/bin/xcrun") {
    self.xcrunPath = xcrunPath
    makeLaunch = nil
  }

  init(
    xcrunPath: String = "/usr/bin/xcrun",
    launch: @escaping @Sendable (SimulatorDevice, String, Codec) -> Launch
  ) {
    self.xcrunPath = xcrunPath
    makeLaunch = launch
  }

  /// Everything `stop()` needs, read under the lock exactly once. Taking the
  /// snapshot here keeps the lock out of the rest of `stop()`, where reaching
  /// for the `session` accessor would deadlock on this same non-recursive lock.
  private func snapshot() -> (process: Process, session: Session, scratch: URL)? {
    lock.lock()
    defer { lock.unlock() }
    guard let process, let currentSession, let scratchDirectory else { return nil }
    return (process, currentSession, scratchDirectory)
  }

  /// Recording has to signal simctl itself, and `xcrun` does not forward SIGINT
  /// to the tool it launches: interrupting `xcrun` would leave the recorder
  /// running and the movie unfinalized. So resolve the real binary once and
  /// spawn that, falling back to `xcrun` if the lookup fails.
  private func simctlExecutable() -> (path: String, leadingArguments: [String]) {
    lock.lock()
    let cached = resolvedSimctlPath
    lock.unlock()
    if let cached { return (cached, []) }

    let lookup = Process()
    lookup.executableURL = URL(fileURLWithPath: xcrunPath)
    lookup.arguments = ["-f", "simctl"]
    let pipe = Pipe()
    lookup.standardOutput = pipe
    lookup.standardError = FileHandle.nullDevice
    do {
      try lookup.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      lookup.waitUntilExit()
      let path = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard lookup.terminationStatus == 0, !path.isEmpty,
        FileManager.default.isExecutableFile(atPath: path)
      else { return (xcrunPath, ["simctl"]) }
      lock.lock()
      resolvedSimctlPath = path
      lock.unlock()
      return (path, [])
    } catch {
      return (xcrunPath, ["simctl"])
    }
  }

  public var session: Session? {
    lock.lock()
    defer { lock.unlock() }
    return currentSession
  }

  public var isRecording: Bool {
    session != nil
  }

  @discardableResult
  public func start(
    device: SimulatorDevice,
    path: String,
    codec: Codec = .h264
  ) throws -> Session {
    lock.lock()
    if let existing = currentSession {
      lock.unlock()
      throw SimctlBuddyError.recordingAlreadyRunning(existing.path)
    }
    lock.unlock()

    let destination = SettingsStore.absolutePath(path)
    try FileManager.default.createDirectory(
      at: URL(fileURLWithPath: destination).deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("simbuddy-record-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let logURL = scratch.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let logHandle = try FileHandle(forWritingTo: logURL)

    let launch: Launch
    if let makeLaunch {
      launch = makeLaunch(device, destination, codec)
    } else {
      let executable = simctlExecutable()
      launch = Launch(
        path: executable.path,
        arguments: executable.leadingArguments + [
          "io", device.udid, "recordVideo",
          "--codec=\(codec.rawValue)", "--force", destination,
        ]
      )
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launch.path)
    process.arguments = launch.arguments
    process.standardOutput = logHandle
    process.standardError = logHandle
    process.standardInput = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      try? logHandle.close()
      try? FileManager.default.removeItem(at: scratch)
      throw SimctlBuddyError.recordingFailed(error.localizedDescription)
    }

    let session = Session(
      deviceUDID: device.udid,
      deviceName: device.name,
      path: destination,
      startedAt: Date()
    )

    lock.lock()
    self.process = process
    currentSession = session
    scratchDirectory = scratch
    lock.unlock()

    if let failure = waitForStartup(process: process, logURL: logURL) {
      if process.isRunning {
        process.interrupt()
        _ = Self.wait(for: process, seconds: Self.escalationTimeout)
        if process.isRunning { process.terminate() }
      }
      try? logHandle.close()
      clear()
      try? FileManager.default.removeItem(at: scratch)
      Self.discardEmptyFile(at: destination)
      throw SimctlBuddyError.recordingFailed(failure)
    }
    try? logHandle.close()
    return session
  }

  /// Sends SIGINT the way Control-C would, then waits for the movie to be
  /// finalized before reporting success.
  @discardableResult
  public func stop() throws -> Session {
    guard let running = snapshot() else { throw SimctlBuddyError.noRecordingRunning }
    let process = running.process
    let session = running.session
    let scratch = running.scratch

    var abandoned = false
    if process.isRunning {
      process.interrupt()
      if !Self.wait(for: process, seconds: Self.shutdownTimeout) {
        // simctl is wedged. Escalate, but never block the interface forever
        // waiting for a process that will not die.
        process.terminate()
        if !Self.wait(for: process, seconds: Self.escalationTimeout) {
          kill(process.processIdentifier, SIGKILL)
          abandoned = !Self.wait(for: process, seconds: Self.escalationTimeout)
        }
      }
    }

    let log = Self.contents(of: scratch.appendingPathComponent("stderr"))
    clear()
    try? FileManager.default.removeItem(at: scratch)

    guard Self.isUsableMovie(at: session.path) else {
      // An empty file reads as a successful capture in a file listing, which is
      // worse than no file at all.
      Self.discardEmptyFile(at: session.path)
      throw SimctlBuddyError.recordingFailed(
        log.isEmpty ? "No video was written to \(session.path)." : log)
    }
    if abandoned {
      throw SimctlBuddyError.recordingFailed(
        "simctl did not exit, so \(session.path) may be incomplete.")
    }
    return session
  }

  /// Best-effort teardown for quitting or crashing: never throws, so it is safe
  /// in a `defer`.
  public func cancel() {
    _ = try? stop()
  }

  /// Nil when the recording is under way, otherwise the reason it is not.
  private func waitForStartup(process: Process, logURL: URL) -> String? {
    let deadline = Date().addingTimeInterval(Self.startupTimeout)
    while Date() < deadline {
      let log = Self.contents(of: logURL)
      if log.contains("Recording started") { return nil }
      // simctl can report a failure and keep running, so the log has to be
      // believed rather than the process being alive.
      if Self.describesFailure(log) { return log }
      if !process.isRunning {
        process.waitUntilExit()
        let detail = Self.contents(of: logURL)
        return detail.isEmpty
          ? "simctl exited with status \(process.terminationStatus) before recording started."
          : detail
      }
      usleep(100_000)
    }
    // Still running and still quiet: an old simctl may not print the banner, so
    // treat a live process as a live recording rather than failing the action.
    return process.isRunning ? nil : Self.contents(of: logURL)
  }

  private func clear() {
    lock.lock()
    process = nil
    currentSession = nil
    scratchDirectory = nil
    lock.unlock()
  }

  /// True when the process exited within the timeout.
  private static func wait(for process: Process, seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while process.isRunning, Date() < deadline {
      usleep(100_000)
    }
    return !process.isRunning
  }

  private static func describesFailure(_ log: String) -> Bool {
    let lowered = log.lowercased()
    return lowered.contains("error starting video recorder")
      || lowered.contains("an error was encountered")
  }

  private static func isUsableMovie(at path: String) -> Bool {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let size = attributes[.size] as? Int
    else { return false }
    return size > 0
  }

  private static func discardEmptyFile(at path: String) {
    guard FileManager.default.fileExists(atPath: path), !isUsableMovie(at: path) else { return }
    try? FileManager.default.removeItem(atPath: path)
  }

  private static func contents(of url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { return "" }
    return String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
