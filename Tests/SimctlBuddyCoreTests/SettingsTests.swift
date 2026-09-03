import Foundation
import XCTest

@testable import SimctlBuddyCore

final class SettingsTests: XCTestCase {
  private var directory: URL!
  private var store: SettingsStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testMissingFileReadsAsDefaults() throws {
    XCTAssertEqual(try store.load(), .empty)
    XCTAssertNil(try store.value(for: .screenshotDirectory))
  }

  func testSettingADirectoryCreatesItAndStoresTheAbsolutePath() throws {
    let target = directory.appendingPathComponent("shots").path
    let resolved = try store.set(.screenshotDirectory, to: target)

    XCTAssertEqual(resolved, target)
    XCTAssertTrue(FileManager.default.fileExists(atPath: target))
    XCTAssertEqual(try store.value(for: .screenshotDirectory), target)
  }

  func testSettingsAreIndependent() throws {
    try store.set(.screenshotDirectory, to: directory.appendingPathComponent("shots").path)
    try store.set(.recordingDirectory, to: directory.appendingPathComponent("movies").path)

    let settings = try store.load()
    XCTAssertTrue(settings.screenshotDirectory?.hasSuffix("shots") == true)
    XCTAssertTrue(settings.recordingDirectory?.hasSuffix("movies") == true)

    try store.clear(.screenshotDirectory)
    XCTAssertNil(try store.load().screenshotDirectory)
    XCTAssertNotNil(try store.load().recordingDirectory)
  }

  func testSettingADirectoryOntoAFileIsRefused() throws {
    let file = directory.appendingPathComponent("occupied")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: file)

    XCTAssertThrowsError(try store.set(.screenshotDirectory, to: file.path)) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .notADirectory(file.path))
    }
  }

  func testExplicitPathWinsOverTheConfiguredDirectory() {
    let settings = Settings(screenshotDirectory: "/configured")
    XCTAssertEqual(
      settings.screenshotDestination(explicit: "/tmp/shot.png", fileName: "ignored.png"),
      "/tmp/shot.png"
    )
  }

  func testConfiguredDirectoryIsUsedWhenNoPathIsGiven() {
    let settings = Settings(screenshotDirectory: "/configured", recordingDirectory: "/movies")
    XCTAssertEqual(
      settings.screenshotDestination(fileName: "shot.png"), "/configured/shot.png")
    XCTAssertEqual(
      settings.recordingDestination(fileName: "clip.mov"), "/movies/clip.mov")
  }

  func testWorkingDirectoryIsTheFallback() {
    let destination = Settings.empty.screenshotDestination(fileName: "shot.png")
    XCTAssertEqual(
      destination,
      SettingsStore.absolutePath(
        NSString(string: FileManager.default.currentDirectoryPath)
          .appendingPathComponent("shot.png"))
    )
  }

  func testCaptureNamesAreTimestampedAndTyped() {
    let date = Date(timeIntervalSince1970: 0)
    XCTAssertTrue(CaptureName.screenshot(at: date).hasSuffix(".png"))
    XCTAssertTrue(CaptureName.recording(at: date).hasSuffix(".mov"))
    XCTAssertTrue(CaptureName.screenshot(at: date).hasPrefix("simbuddy-"))
  }

  func testEverySettingHasACommandLineName() {
    XCTAssertEqual(SettingsKey.allCases.count, 3)
    for key in SettingsKey.allCases {
      XCTAssertFalse(key.rawValue.contains(" "))
      XCTAssertFalse(key.summary.isEmpty)
    }
  }
}
