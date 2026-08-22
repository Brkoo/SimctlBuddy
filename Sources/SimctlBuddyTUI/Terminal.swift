import Darwin
import Foundation

enum TerminalKey: Equatable {
  case up
  case down
  case left
  case right
  case enter
  case escape
  case tab
  case backspace
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

final class TerminalSession {
  private var originalSettings = termios()
  private var isActive = false

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
    raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)
    withUnsafeMutableBytes(of: &raw.c_cc) { bytes in
      bytes[Int(VMIN)] = 0
      bytes[Int(VTIME)] = 1
    }

    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
      throw TerminalError.cannotEnableRawMode
    }
    isActive = true
    write("\u{001B}[?1049h\u{001B}[?25l\u{001B}[2J\u{001B}[H")
  }

  func stop() {
    guard isActive else { return }
    var settings = originalSettings
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings)
    write("\u{001B}[?25h\u{001B}[?1049l")
    isActive = false
  }

  deinit {
    stop()
  }

  func write(_ value: String) {
    FileHandle.standardOutput.write(Data(value.utf8))
  }

  func readKey() -> TerminalKey? {
    var bytes = [UInt8](repeating: 0, count: 64)
    let count = bytes.withUnsafeMutableBytes { buffer in
      Darwin.read(STDIN_FILENO, buffer.baseAddress, buffer.count)
    }
    guard count > 0 else { return nil }
    let input = Array(bytes.prefix(count))

    if input.starts(with: [27, 91, 65]) { return .up }
    if input.starts(with: [27, 91, 66]) { return .down }
    if input.starts(with: [27, 91, 67]) { return .right }
    if input.starts(with: [27, 91, 68]) { return .left }

    switch input[0] {
    case 9: return .tab
    case 10, 13: return .enter
    case 27: return .escape
    case 8, 127: return .backspace
    default:
      let printable = input.filter { $0 >= 32 || $0 >= 128 }
      guard !printable.isEmpty else { return nil }
      return .text(String(decoding: printable, as: UTF8.self))
    }
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
