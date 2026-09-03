import Foundation
import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

/// Rows wider than the window wrap, push the rest of the frame down, and
/// scroll — which is how pieces of earlier frames end up on screen with several
/// rows looking selected at once. Every row has to fit in *columns*, and almost
/// every glyph this interface draws is ambiguous-width, so "fits" depends on the
/// terminal.
final class DisplayWidthTests: XCTestCase {
  private let devices = [
    SimulatorDevice(
      name: "iPhone 17 Pro", udid: "AAAA-BBBB", state: "Booted", isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5"),
    SimulatorDevice(
      name: "iDart iPad Pro 11", udid: "CCCC-DDDD", state: "Shutdown", isAvailable: true,
      runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5"),
  ]

  private func populated() -> TUIState {
    var state = TUIState(devices: devices)
    state.links = [
      SavedLink(name: "Purchase popup", url: "sparatappqa://navigate/purchasepopup"),
      SavedLink(name: "Staging-Slot", url: "sparatappqa://automation?staging-slot=staging5"),
      SavedLink(name: "StagingSlot-SI", url: "sparsiappqa://automation?staging-slot=staging"),
    ]
    state.apps = [
      SavedApp(
        name: "SparAT", bundleIdentifier: "at.spar.mobile.spar-app.ent.qa",
        scheme: "sparatappqa")
    ]
    state.paths = [SavedPath(name: "Staging", path: "/builds/Staging.app")]
    state.output = [
      "✗ Command failed (194): xcrun simctl openurl E6DACCE1 sparsiappqa://automation",
      "  (OSStatus error -10814.)",
      "✓ Launched at.spar.mobile.spar-app.ent.qa",
    ]
    state.busy = "Opening Staging-Slot"
    return state
  }

  /// Strips the colour escapes so what is left is what occupies columns.
  private func visibleRows(_ screen: String) -> [String] {
    screen
      .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
      .components(separatedBy: "\r\n")
  }

  private let sizes = [(78, 18), (90, 20), (100, 24), (120, 34), (132, 40), (200, 50)]

  func testNoRowIsWiderThanTheWindowOnANarrowTerminal() {
    let metrics = DisplayMetrics(ambiguousWidth: 1)
    let renderer = TUIRenderer(metrics: metrics)
    for (columns, rows) in sizes {
      let screen = renderer.render(state: populated(), columns: columns, rows: rows)
      for row in visibleRows(screen) {
        XCTAssertLessThanOrEqual(
          metrics.width(of: row), columns,
          "row is \(metrics.width(of: row)) columns wide at \(columns)x\(rows): \(row)")
      }
    }
  }

  /// The regression: a terminal that draws ambiguous glyphs two columns wide.
  func testNoRowIsWiderThanTheWindowWhenGlyphsAreDoubleWidth() {
    let metrics = DisplayMetrics(ambiguousWidth: 2)
    let renderer = TUIRenderer(metrics: metrics)
    for (columns, rows) in sizes {
      let screen = renderer.render(state: populated(), columns: columns, rows: rows)
      for row in visibleRows(screen) {
        XCTAssertLessThanOrEqual(
          metrics.width(of: row), columns,
          "row is \(metrics.width(of: row)) columns wide at \(columns)x\(rows): \(row)")
      }
    }
  }

  func testDialogsAlsoFitWhenGlyphsAreDoubleWidth() {
    let metrics = DisplayMetrics(ambiguousWidth: 2)
    let renderer = TUIRenderer(metrics: metrics)
    var state = populated()
    var prompt = TUIPrompt(kind: .installApp, label: "Path to .app", value: "~/Developer/")
    prompt.candidates = (1...20).map { "Directory-\($0)/" }
    prompt.note = "20 matches"
    state.prompt = prompt

    for (columns, rows) in sizes {
      let screen = renderer.render(state: state, columns: columns, rows: rows)
      // Overlay rows are positioned individually, so measure each written run.
      for part in screen.components(separatedBy: "\u{001B}[") {
        guard let match = part.range(of: "^[0-9]+;([0-9]+)H", options: .regularExpression)
        else { continue }
        let header = String(part[match])
        guard
          let semicolon = header.lastIndex(of: ";"),
          let column = Int(header[header.index(after: semicolon)..<header.index(before: header.endIndex)])
        else { continue }
        let content = String(part[match.upperBound...])
          .replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        XCTAssertLessThanOrEqual(
          column - 1 + metrics.width(of: content), columns,
          "dialog row overflows at \(columns)x\(rows)")
      }
    }
  }

  func testAsciiIsAlwaysOneColumn() {
    for metrics in [DisplayMetrics.narrow, DisplayMetrics(ambiguousWidth: 2)] {
      XCTAssertEqual(metrics.width(of: "iPhone 17 Pro"), 13)
      XCTAssertEqual(metrics.width(of: ""), 0)
    }
  }

  func testTheGlyphsThisInterfaceUsesFollowTheTerminal() {
    let narrow = DisplayMetrics.narrow
    let wide = DisplayMetrics(ambiguousWidth: 2)
    for glyph in ["●", "○", "▶", "↗", "…", "·", "─", "│", "┌", "▌", "→", "×", "—"] {
      XCTAssertEqual(narrow.width(of: glyph), 1, "\(glyph) should be 1 when narrow")
      XCTAssertEqual(wide.width(of: glyph), 2, "\(glyph) should be 2 when wide")
    }
  }

  func testEmojiAndCJKAreAlwaysTwoColumns() {
    for metrics in [DisplayMetrics.narrow, DisplayMetrics(ambiguousWidth: 2)] {
      XCTAssertEqual(metrics.width(of: "🚀"), 2)
      XCTAssertEqual(metrics.width(of: "日本"), 4)
    }
  }

  func testCombiningMarksAddNothing() {
    let metrics = DisplayMetrics.narrow
    XCTAssertEqual(metrics.width(of: "e\u{0301}"), 1)
  }

  func testTruncationNeverLeavesHalfOfAWideGlyph() {
    let metrics = DisplayMetrics(ambiguousWidth: 2)
    // "●●●" is six columns; five columns can only hold two of them.
    XCTAssertEqual(metrics.truncate("●●●", to: 5), "●●")
    XCTAssertEqual(metrics.width(of: metrics.truncate("●●●", to: 5)), 4)
    XCTAssertEqual(metrics.truncate("abc", to: 2), "ab")
    XCTAssertEqual(metrics.truncate("abc", to: 0), "")
  }

  func testPaddingReachesExactlyTheTargetWidth() {
    for metrics in [DisplayMetrics.narrow, DisplayMetrics(ambiguousWidth: 2)] {
      XCTAssertEqual(metrics.width(of: metrics.pad("● iPhone", to: 20)), 20)
      XCTAssertEqual(metrics.width(of: metrics.pad("", to: 7)), 7)
      // Over-long input is cut to fit rather than overflowing.
      XCTAssertLessThanOrEqual(metrics.width(of: metrics.pad("●●●●●●", to: 5)), 5)
    }
  }

  func testAmbiguousWidthIsClampedToSomethingSensible() {
    XCTAssertEqual(DisplayMetrics(ambiguousWidth: 0).ambiguousWidth, 1)
    XCTAssertEqual(DisplayMetrics(ambiguousWidth: 9).ambiguousWidth, 2)
  }
}
