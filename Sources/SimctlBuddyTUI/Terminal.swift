import Darwin
import Foundation

enum TerminalKey: Equatable {
  case interrupt
  case up
  case down
  case left
  case right
  case enter
  case escape
  case tab
  case backspace
  case clearLine
  case text(String)
}

struct TerminalSize: Equatable {
  var columns: Int
  var rows: Int
}

enum TerminalError: LocalizedError {
  case notInteractive
  case cannotReadSettings
  case cannotEnableRawMode

  var errorDescription: String? {
    switch self {
    case .notInteractive:
      return "The interactive UI needs a terminal. Use `simbuddy --help` for scriptable commands."
    case .cannotReadSettings:
      return "Could not read terminal settings."
    case .cannotEnableRawMode:
      return "Could not enable interactive terminal mode."
    }
  }
}

/// Signal handlers cannot touch instance state, so the settings needed to put
/// the terminal back live here and are restored by an async-signal-safe path.
private nonisolated(unsafe) var terminalRestoreSettings = termios()
private nonisolated(unsafe) var terminalRestoreArmed = false

/// Show the cursor, re-enable auto-wrap, leave the alternate screen.
private let terminalResetSequence = "\u{001B}[?25h\u{001B}[?7h\u{001B}[?1049l"

private func restoreTerminalState() {
  guard terminalRestoreArmed else { return }
  terminalRestoreArmed = false
  tcsetattr(STDIN_FILENO, TCSAFLUSH, &terminalRestoreSettings)
  _ = terminalResetSequence.withCString { pointer in
    write(STDOUT_FILENO, pointer, strlen(pointer))
  }
}

private func handleFatalSignal(_ number: Int32) {
  restoreTerminalState()
  signal(number, SIG_DFL)
  raise(number)
}

final class TerminalSession {
  private var originalSettings = termios()
  private var isActive = false
  private var pending = [UInt8]()

  func start() throws {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
      throw TerminalError.notInteractive
    }
    guard tcgetattr(STDIN_FILENO, &originalSettings) == 0 else {
      throw TerminalError.cannotReadSettings
    }

    var raw = originalSettings
    raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
    raw.c_oflag &= ~tcflag_t(OPOST)
    raw.c_cflag |= tcflag_t(CS8)
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
    withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
      bytes[Int(VMIN)] = 0
      bytes[Int(VTIME)] = 1
    }

    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
      throw TerminalError.cannotEnableRawMode
    }
    isActive = true
    terminalRestoreSettings = originalSettings
    terminalRestoreArmed = true
    // A killed process would otherwise leave the terminal in raw mode with the
    // alternate screen still active and the cursor hidden.
    for number in [SIGTERM, SIGHUP, SIGQUIT, SIGINT] {
      signal(number, handleFatalSignal)
    }
    // Auto-wrap off is what keeps a frame from destroying itself. Any row that
    // ends up wider than the window — a glyph the terminal draws two columns
    // wide where we counted one — would otherwise wrap, push every later row
    // down, and scroll the screen, leaving pieces of earlier frames behind.
    // Clipped at the right edge is a cosmetic problem; scrolling is not.
    write("\u{001B}[?1049h\u{001B}[?25l\u{001B}[?7l\u{001B}[2J\u{001B}[H")
  }

  func stop() {
    guard isActive else { return }
    var settings = originalSettings
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings)
    write(terminalResetSequence)
    isActive = false
    terminalRestoreArmed = false
    for number in [SIGTERM, SIGHUP, SIGQUIT, SIGINT] {
      signal(number, SIG_DFL)
    }
  }

  deinit {
    stop()
  }

  func write(_ value: String) {
    FileHandle.standardOutput.write(Data(value.utf8))
  }

  /// Wipes the whole screen. Shrinking a window leaves the emulator holding
  /// cells the new, smaller frame never writes over, so a resize repaints from
  /// a clean slate rather than on top of the old layout.
  func clear() {
    write("\u{001B}[2J\u{001B}[H")
  }

  /// Reads one key per call, buffering whatever else arrived in the same chunk.
  /// Fast typing and pastes deliver several bytes at once, so decoding the whole
  /// chunk as a single key would swallow shortcuts.
  func readKey() -> TerminalKey? {
    if pending.isEmpty {
      var bytes = [UInt8](repeating: 0, count: 1024)
      let count = bytes.withUnsafeMutableBytes { buffer in
        Darwin.read(STDIN_FILENO, buffer.baseAddress, buffer.count)
      }
      guard count > 0 else { return nil }
      pending = Array(bytes.prefix(count))
    }
    return nextBufferedKey()
  }

  private func nextBufferedKey() -> TerminalKey? {
    while !pending.isEmpty {
      if pending.count >= 3, pending[0] == 27, pending[1] == 91 {
        let code = pending[2]
        pending.removeFirst(3)
        switch code {
        case 65: return .up
        case 66: return .down
        case 67: return .right
        case 68: return .left
        default: continue
        }
      }

      let byte = pending.removeFirst()
      switch byte {
      case 3: return .interrupt
      case 9: return .tab
      case 10, 13: return .enter
      case 27: return .escape
      case 8, 127: return .backspace
      case 21: return .clearLine
      default:
        guard byte >= 32 else { continue }
        var scalar = [byte]
        let continuations = Self.continuationCount(for: byte)
        while scalar.count <= continuations, !pending.isEmpty {
          scalar.append(pending.removeFirst())
        }
        if let text = String(bytes: scalar, encoding: .utf8), !text.isEmpty {
          return .text(text)
        }
        continue
      }
    }
    return nil
  }

  private static func continuationCount(for byte: UInt8) -> Int {
    switch byte {
    case 0xC0..<0xE0: return 1
    case 0xE0..<0xF0: return 2
    case 0xF0...: return 3
    default: return 0
    }
  }

  /// Asks the terminal how wide it actually draws an ambiguous-width glyph.
  ///
  /// Prints one at a known column, then reads back where the cursor ended up.
  /// A terminal that does not answer leaves the interface assuming one column,
  /// which is the common case.
  /// Set `SIMBUDDY_AMBIGUOUS_WIDTH=1` or `2` to skip the probe, for a terminal
  /// that does not answer it or answers wrongly.
  static let widthOverrideKey = "SIMBUDDY_AMBIGUOUS_WIDTH"

  func measureAmbiguousWidth() -> Int {
    if let override = ProcessInfo.processInfo.environment[Self.widthOverrideKey],
      let value = Int(override.trimmingCharacters(in: .whitespaces)),
      (1...2).contains(value)
    {
      return value
    }
    guard isActive else { return 1 }
    // Bottom-left, which the following clear wipes anyway.
    write("\u{001B}[999;1H●\u{001B}[6n")
    let measured = readCursorColumn()
    write("\u{001B}[2J\u{001B}[H")
    guard let measured else { return 1 }
    // The glyph started at column 1, so the cursor sits one past its width.
    return measured >= 3 ? 2 : 1
  }

  /// Reads a `ESC[row;colR` cursor report, giving up quickly if none comes.
  private func readCursorColumn() -> Int? {
    var response = [UInt8]()
    // Reads return after VTIME (0.1s), so this waits at most about half a second.
    for _ in 0..<5 {
      var bytes = [UInt8](repeating: 0, count: 64)
      let count = bytes.withUnsafeMutableBytes { buffer in
        Darwin.read(STDIN_FILENO, buffer.baseAddress, buffer.count)
      }
      if count > 0 { response += bytes.prefix(count) }
      if response.contains(UInt8(ascii: "R")) { break }
    }

    guard
      let terminator = response.firstIndex(of: UInt8(ascii: "R")),
      let text = String(bytes: response[..<terminator], encoding: .utf8),
      let semicolon = text.lastIndex(of: ";")
    else {
      // Anything that was not the report is a keypress; keep it for the loop.
      pending += response
      return nil
    }

    // Whatever arrived after the report is real input.
    pending += response[(terminator + 1)...]
    return Int(text[text.index(after: semicolon)...])
  }

  func size() -> TerminalSize {
    var window = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0 else {
      return TerminalSize(columns: 120, rows: 36)
    }
    return TerminalSize(
      columns: max(1, Int(window.ws_col)),
      rows: max(1, Int(window.ws_row))
    )
  }
}
