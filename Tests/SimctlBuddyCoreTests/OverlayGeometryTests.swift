import Foundation
import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

/// A dialog that runs past the edge of the window leaves rows of the previous
/// frame stranded on screen — the "two input fields" report. These pin every
/// overlay inside the window at every size the interface claims to support.
final class OverlayGeometryTests: XCTestCase {
  private let devices = [
    SimulatorDevice(
      name: "iPhone 17 Pro", udid: "AAAA", state: "Booted", isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
  ]

  /// Every `ESC[row;colH` in the output, as (row, column) pairs.
  private func positions(in screen: String) -> [(row: Int, column: Int)] {
    let pattern = try! NSRegularExpression(pattern: "\u{001B}\\[(\\d+);(\\d+)H")
    let range = NSRange(screen.startIndex..<screen.endIndex, in: screen)
    return pattern.matches(in: screen, range: range).compactMap { match in
      guard
        let rowRange = Range(match.range(at: 1), in: screen),
        let columnRange = Range(match.range(at: 2), in: screen),
        let row = Int(screen[rowRange]),
        let column = Int(screen[columnRange])
      else { return nil }
      return (row, column)
    }
  }

  /// Width of a rendered line once the colour escapes are removed.
  private func plainWidth(of line: String) -> Int {
    let stripped = line.replacingOccurrences(
      of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
    return stripped.count
  }

  private func overlayRows(in screen: String) -> [(row: Int, column: Int, width: Int)] {
    // Split on the cursor moves so each overlay row can be measured.
    let parts = screen.components(separatedBy: "\u{001B}[")
    var result = [(row: Int, column: Int, width: Int)]()
    let pattern = try! NSRegularExpression(pattern: "^(\\d+);(\\d+)H")
    for part in parts {
      let range = NSRange(part.startIndex..<part.endIndex, in: part)
      guard let match = pattern.firstMatch(in: part, range: range),
        let rowRange = Range(match.range(at: 1), in: part),
        let columnRange = Range(match.range(at: 2), in: part),
        let row = Int(part[rowRange]),
        let column = Int(part[columnRange])
      else { continue }
      let content = String(part[Range(match.range, in: part)!.upperBound...])
      result.append((row, column, plainWidth(of: content)))
    }
    return result
  }

  private var sizes: [(columns: Int, rows: Int)] {
    [(78, 18), (80, 18), (80, 20), (90, 20), (100, 24), (132, 40), (200, 60), (400, 100)]
  }

  func testPromptWithManyMatchesStaysInsideEverySupportedWindow() {
    let candidates = (1...40).map { "Directory-\($0)/" }
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "~/Developer/")
    prompt.candidates = candidates
    prompt.note = "\(candidates.count) matches"

    for size in sizes {
      var state = TUIState(devices: devices)
      state.prompt = prompt

      let screen = TUIRenderer().render(state: state, columns: size.columns, rows: size.rows)

      for placed in overlayRows(in: screen) {
        XCTAssertLessThanOrEqual(
          placed.row, size.rows,
          "row \(placed.row) is past the bottom at \(size.columns)x\(size.rows)")
        XCTAssertGreaterThanOrEqual(placed.row, 1)
        // Touching the final column arms auto-wrap, which scrolls the screen.
        XCTAssertLessThan(
          placed.column + placed.width - 1, size.columns + 1,
          "row \(placed.row) runs past the right edge at \(size.columns)x\(size.rows)")
      }
    }
  }

  func testPickerWithALongListStaysInsideEverySupportedWindow() {
    let options = (1...60).map {
      TUIPickerOption(value: "com.example.App\($0)", label: "com.example.App\($0)", detail: "installed")
    }

    for size in sizes {
      var state = TUIState(devices: devices)
      state.picker = TUIPicker(
        purpose: .launchApp, title: "Launch app", options: options, isLoading: false)

      let screen = TUIRenderer().render(state: state, columns: size.columns, rows: size.rows)

      for placed in overlayRows(in: screen) {
        XCTAssertLessThanOrEqual(
          placed.row, size.rows,
          "row \(placed.row) is past the bottom at \(size.columns)x\(size.rows)")
        XCTAssertLessThan(
          placed.column + placed.width - 1, size.columns + 1,
          "row \(placed.row) runs past the right edge at \(size.columns)x\(size.rows)")
      }
    }
  }

  func testShortWindowsListFewerMatchesRatherThanOverflowing() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "~/Developer/")
    prompt.candidates = (1...40).map { "Directory-\($0)/" }
    prompt.note = "40 matches"

    var state = TUIState(devices: devices)
    state.prompt = prompt

    let short = TUIRenderer().render(state: state, columns: 90, rows: 18)
    let tall = TUIRenderer().render(state: state, columns: 90, rows: 44)

    // The tall window has room for the candidate list; the short one gives it up.
    XCTAssertTrue(tall.contains("Directory-1/"))
    XCTAssertGreaterThan(
      overlayRows(in: tall).count, overlayRows(in: short).count,
      "a short window should produce a shorter dialog")
  }

  func testTheDialogIsDrawnExactlyOnce() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "~/Dev")
    prompt.candidates = ["Developer/", "Desktop/"]
    prompt.note = "2 matches"

    for size in sizes {
      var state = TUIState(devices: devices)
      state.prompt = prompt

      let screen = TUIRenderer().render(state: state, columns: size.columns, rows: size.rows)

      // One input field, and one title, per frame.
      XCTAssertEqual(
        screen.components(separatedBy: "›").count - 1, 1,
        "expected one input field at \(size.columns)x\(size.rows)")
      XCTAssertEqual(
        screen.components(separatedBy: "Install app").count - 1, 1,
        "expected one dialog title at \(size.columns)x\(size.rows)")
    }
  }

  func testOverlayRowsAreContiguousSoNothingShowsThrough() {
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "~/Developer/")
    prompt.candidates = (1...12).map { "Directory-\($0)/" }
    prompt.note = "12 matches"

    var state = TUIState(devices: devices)
    state.prompt = prompt

    let screen = TUIRenderer().render(state: state, columns: 100, rows: 24)
    let placed = overlayRows(in: screen)

    XCTAssertGreaterThan(placed.count, 1)
    for (previous, next) in zip(placed, placed.dropFirst()) {
      XCTAssertEqual(next.row, previous.row + 1, "the dialog skipped a row")
      XCTAssertEqual(next.column, previous.column, "the dialog changed column mid-box")
    }
  }
}
