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

  /// Counting the keys only broke every time one was added, which said nothing
  /// about whether the new one was usable. What matters is that each is
  /// nameable on the command line and unique.
  func testEverySettingHasACommandLineName() {
    XCTAssertFalse(SettingsKey.allCases.isEmpty)
    for key in SettingsKey.allCases {
      XCTAssertFalse(key.rawValue.contains(" "), "\(key) has a space in its name")
      XCTAssertFalse(key.summary.isEmpty, "\(key) has no summary")
      XCTAssertEqual(key.rawValue, key.rawValue.lowercased())
    }
    let names = SettingsKey.allCases.map(\.rawValue)
    XCTAssertEqual(Set(names).count, names.count, "two settings share a name")
  }
}

final class PanelWidthSettingTests: XCTestCase {
  private var directory: URL!
  private var store: SettingsStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("panel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testAFractionIsStoredAndReadBack() throws {
    try store.set(.devicePanelWidth, to: "0.45")
    XCTAssertEqual(try store.load().devicePanelWidth, 0.45)
    XCTAssertEqual(try store.value(for: .devicePanelWidth), "0.45")
  }

  /// Both ways of writing a share mean the same thing.
  func testAPercentageMeansTheSameAsAFraction() throws {
    try store.set(.actionPanelWidth, to: "45%")
    XCTAssertEqual(try XCTUnwrap(store.load().actionPanelWidth), 0.45, accuracy: 0.0001)
  }

  /// A share above one can only have been meant as a percentage.
  func testABareNumberAboveOneIsReadAsAPercentage() throws {
    try store.set(.devicePanelWidth, to: "45")
    XCTAssertEqual(try XCTUnwrap(store.load().devicePanelWidth), 0.45, accuracy: 0.0001)
  }

  func testSpacesAroundAPercentageAreTolerated() throws {
    try store.set(.devicePanelWidth, to: " 40 % ")
    XCTAssertEqual(try XCTUnwrap(store.load().devicePanelWidth), 0.40, accuracy: 0.0001)
  }

  func testValuesOutsideTheUsableRangeAreRefused() {
    for value in ["0", "0.05", "0.7", "95%", "-0.3", "1.5"] {
      XCTAssertThrowsError(
        try store.set(.devicePanelWidth, to: value), "\(value) should be refused")
    }
  }

  func testNonsenseIsRefusedWithAnExplanation() {
    XCTAssertThrowsError(try store.set(.devicePanelWidth, to: "wide")) { error in
      let text = error.localizedDescription
      XCTAssertTrue(text.contains("0.45"))
      XCTAssertTrue(text.contains("45%"))
    }
    XCTAssertThrowsError(try store.set(.devicePanelWidth, to: ""))
  }

  /// A width setting is not a path, so it must never be turned into a folder.
  func testSettingAWidthCreatesNoDirectory() throws {
    try store.set(.devicePanelWidth, to: "0.4")
    let stray = directory.appendingPathComponent("0.4")
    XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path))
  }

  func testClearingRestoresTheDefault() throws {
    try store.set(.devicePanelWidth, to: "0.4")
    try store.clear(.devicePanelWidth)
    XCTAssertNil(try store.load().devicePanelWidth)
  }

  func testOnlyWidthsAreMarkedAsFractions() {
    XCTAssertTrue(SettingsKey.devicePanelWidth.isFraction)
    XCTAssertTrue(SettingsKey.actionPanelWidth.isFraction)
    XCTAssertFalse(SettingsKey.screenshotDirectory.isFraction)
    XCTAssertFalse(SettingsKey.firebaseServiceAccount.isFraction)
  }
}
