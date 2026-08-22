import Foundation

public struct CommandResult: Sendable, Equatable {
  public let standardOutput: String
  public let standardError: String
  public let exitCode: Int32

  public init(standardOutput: String, standardError: String, exitCode: Int32) {
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitCode = exitCode
  }
}

public protocol CommandRunning: Sendable {
  func run(
    executable: String,
    arguments: [String],
    standardInput: Data?
  ) throws -> CommandResult
}

extension CommandRunning {
  public func run(executable: String, arguments: [String]) throws -> CommandResult {
    try run(executable: executable, arguments: arguments, standardInput: nil)
  }
}

public struct ProcessRunner: CommandRunning {
  public init() {}

  public func run(
    executable: String,
    arguments: [String],
    standardInput: Data? = nil
  ) throws -> CommandResult {
    let process = Process()
    let inputPipe = standardInput == nil ? nil : Pipe()
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("simbuddy-\(UUID().uuidString)", isDirectory: true)
    let outputURL = temporaryDirectory.appendingPathComponent("stdout")
    let errorURL = temporaryDirectory.appendingPathComponent("stderr")

    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
      try? outputHandle.close()
      try? errorHandle.close()
    }

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputHandle
    process.standardError = errorHandle
    process.standardInput = inputPipe

    try process.run()

    if let standardInput, let inputPipe {
      inputPipe.fileHandleForWriting.write(standardInput)
      try? inputPipe.fileHandleForWriting.close()
    }

    process.waitUntilExit()
    try outputHandle.synchronize()
    try errorHandle.synchronize()

    return CommandResult(
      standardOutput: String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
      standardError: String(decoding: try Data(contentsOf: errorURL), as: UTF8.self),
      exitCode: process.terminationStatus
    )
  }
}
