import Foundation
import XCTest

@testable import SimctlBuddyCore

final class RecorderTests: XCTestCase {
  private let device = SimulatorDevice(
    name: "iPhone 16", udid: "AAAA", state: "Booted", isAvailable: true)

  private func temporaryPath(_ extension: String = "mov") -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).\(`extension`)").path
  }

  /// A stand-in for simctl: announces itself the way simctl does, writes
  /// something to the destination, then waits to be signalled.
  private func fakeRecorder(writesOutput: Bool = true) -> Recorder {
    Recorder { _, destination, _ in
      let write = writesOutput ? "printf recorded > '\(destination)'; " : ""
      return Recorder.Launch(
        path: "/bin/sh",
        arguments: ["-c", "echo 'Recording started' >&2; \(write)sleep 300"]
      )
    }
  }

  /// The deadlock this guards against only happens while a recording is live:
  /// `stop()` held the lock and then read the `session` accessor, which takes
  /// the same non-recursive lock. With nothing running, `stop()` returns before
  /// ever reaching that line, so the regression needs a running process.
  ///
  /// Note that a regression shows up as this test timing out and the suite then
  /// hanging on the deadlocked thread, rather than as a clean failure — a hung
  /// test run here means the lock is being taken twice again.
  func testStoppingALiveRecordingDoesNotDeadlock() throws {
    let recorder = fakeRecorder()
    let destination = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: destination) }

    let session = try recorder.start(device: device, path: destination)
    XCTAssertTrue(recorder.isRecording)

    let finished = expectation(description: "stop() returned")
    var stopped: Recorder.Session?
    var thrown: Error?
    DispatchQueue.global().async {
      do { stopped = try recorder.stop() } catch { thrown = error }
      finished.fulfill()
    }

    wait(for: [finished], timeout: 20)
    XCTAssertNil(thrown)
    XCTAssertEqual(stopped?.path, session.path)
    XCTAssertFalse(recorder.isRecording)
  }

  func testStoppingReportsAFailureWhenNoVideoWasWritten() throws {
    let recorder = fakeRecorder(writesOutput: false)
    let destination = temporaryPath()

    _ = try recorder.start(device: device, path: destination)

    let finished = expectation(description: "stop() returned")
    var thrown: Error?
    DispatchQueue.global().async {
      do { _ = try recorder.stop() } catch { thrown = error }
      finished.fulfill()
    }
    wait(for: [finished], timeout: 20)

    XCTAssertNotNil(thrown)
    XCTAssertFalse(recorder.isRecording)
    // An empty file in a folder of screenshots reads as a successful capture.
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
  }

  func testASecondRecordingIsRefusedWhileOneIsRunning() throws {
    let recorder = fakeRecorder()
    let destination = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: destination) }

    let session = try recorder.start(device: device, path: destination)
    XCTAssertThrowsError(try recorder.start(device: device, path: temporaryPath())) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .recordingAlreadyRunning(session.path))
    }
    _ = try? recorder.stop()
  }

  func testCancellingStopsALiveRecordingWithoutThrowing() throws {
    let recorder = fakeRecorder()
    let destination = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: destination) }

    _ = try recorder.start(device: device, path: destination)

    let finished = expectation(description: "cancel() returned")
    DispatchQueue.global().async {
      recorder.cancel()
      finished.fulfill()
    }
    wait(for: [finished], timeout: 20)

    XCTAssertFalse(recorder.isRecording)
  }

  func testStartingIsRefusedWhenTheToolReportsAFailure() {
    // simctl can print an error and keep running; that is still a failure.
    let recorder = Recorder { _, _, _ in
      Recorder.Launch(
        path: "/bin/sh",
        arguments: ["-c", "echo 'Error starting video recorder: busy' >&2; sleep 300"]
      )
    }
    let destination = temporaryPath()

    XCTAssertThrowsError(try recorder.start(device: device, path: destination))
    XCTAssertFalse(recorder.isRecording)
  }

  func testStoppingWhenNothingIsRunningThrowsInsteadOfHanging() {
    let recorder = Recorder()
    let finished = expectation(description: "stop() returned")
    var thrown: Error?

    DispatchQueue.global().async {
      do {
        _ = try recorder.stop()
      } catch {
        thrown = error
      }
      finished.fulfill()
    }

    wait(for: [finished], timeout: 5)
    XCTAssertEqual(thrown as? SimctlBuddyError, .noRecordingRunning)
  }

  func testCancellingWhenNothingIsRunningIsSafeAndSilent() {
    let recorder = Recorder()
    let finished = expectation(description: "cancel() returned")

    DispatchQueue.global().async {
      recorder.cancel()
      finished.fulfill()
    }

    wait(for: [finished], timeout: 5)
    XCTAssertFalse(recorder.isRecording)
  }

  func testAFreshRecorderHasNoSession() {
    let recorder = Recorder()
    XCTAssertNil(recorder.session)
    XCTAssertFalse(recorder.isRecording)
  }

  func testSessionDescribesTheCaptureForTheInterface() {
    let started = Date(timeIntervalSinceNow: -90)
    let session = Recorder.Session(
      deviceUDID: "AAAA",
      deviceName: "iPhone 16",
      path: "/movies/simbuddy-20260901-101129.mov",
      startedAt: started
    )

    XCTAssertEqual(session.fileName, "simbuddy-20260901-101129.mov")
    XCTAssertEqual(session.duration(at: started.addingTimeInterval(90)), 90, accuracy: 0.01)
    // A clock that jumped backwards should not produce a negative duration.
    XCTAssertEqual(session.duration(at: started.addingTimeInterval(-10)), 0)
  }

  func testCodecsCoverBothOptionsSimctlAccepts() {
    XCTAssertEqual(Recorder.Codec.allCases.map(\.rawValue).sorted(), ["h264", "hevc"])
  }

  func testStartingRefusesACommandThatCannotRun() {
    let recorder = Recorder { _, _, _ in
      Recorder.Launch(path: "/nonexistent/tool", arguments: [])
    }
    let destination = temporaryPath()

    XCTAssertThrowsError(try recorder.start(device: device, path: destination)) { error in
      guard case .recordingFailed = error as? SimctlBuddyError else {
        return XCTFail("expected a recordingFailed error, got \(error)")
      }
    }
    XCTAssertFalse(recorder.isRecording)
    // Nothing usable was produced, so nothing should be left behind.
    XCTAssertFalse(FileManager.default.fileExists(atPath: destination))
  }
}
