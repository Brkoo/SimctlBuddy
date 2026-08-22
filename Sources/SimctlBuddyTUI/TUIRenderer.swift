import Foundation

public struct TUIRenderer: Sendable {
  public init() {}

  public func render(state: TUIState, columns: Int, rows: Int) -> String {
    guard columns >= 78, rows >= 18 else {
      return
        "\u{001B}[H\u{001B}[2JSimctlBuddy needs at least 78×18 columns. Current size: \(columns)×\(rows)"
    }

    let headerHeight = 2
    let footerHeight = 2
    let bodyHeight = rows - headerHeight - footerHeight
    let deviceWidth = min(38, max(28, columns * 30 / 100))
    let actionWidth = min(38, max(28, columns * 30 / 100))
    let outputWidth = columns - deviceWidth - actionWidth

    var lines = [String]()
    lines.append(style(" SIMCTLBUDDY ", .boldCyan) + "  iOS Simulator control deck")
    let selected =
      state.selectedDevice.map {
        "\($0.name) · \($0.runtimeName) · \($0.state)"
      } ?? "No simulator selected"
    lines.append(" " + truncate(selected, width: columns - 1))

    let deviceLines = state.devices.map { device in
      let dot = device.isBooted ? "●" : "○"
      return "\(dot) \(device.name)  \(device.runtimeName)"
    }
    let actionLines = state.actions.map { action in
      action.hint.isEmpty ? action.title : "\(action.title)  [\(action.hint)]"
    }
    let detailLines = state.showingHelp ? helpLines : outputLines(state: state)

    let devices = box(
      title: "Devices \(state.devices.count)",
      width: deviceWidth,
      height: bodyHeight,
      lines: deviceLines,
      selected: state.selectedDeviceIndex,
      focused: state.focus == .devices
    )
    let actions = box(
      title: "Actions",
      width: actionWidth,
      height: bodyHeight,
      lines: actionLines,
      selected: state.selectedActionIndex,
      focused: state.focus == .actions
    )
    let output = box(
      title: state.showingHelp ? "Help" : "Details / Output",
      width: outputWidth,
      height: bodyHeight,
      lines: detailLines,
      selected: nil,
      focused: false
    )

    for index in 0..<bodyHeight {
      lines.append(devices[index] + actions[index] + output[index])
    }

    if let prompt = state.prompt {
      let available = max(0, columns - prompt.label.count - 5)
      lines.append(
        style(" \(prompt.label): ", .boldYellow) + truncate(prompt.value, width: available) + "▌")
      lines.append(" Enter confirm · Esc cancel · Backspace delete")
    } else {
      lines.append(" ↑/k ↓/j navigate · ←/h →/l switch panel · Enter run · o deep link · r refresh")
      lines.append(" q quit · ? help   " + style("Actions target the selected simulator", .dim))
    }

    return "\u{001B}[H" + lines.prefix(rows).joined(separator: "\r\n") + "\u{001B}[J"
  }

  private var helpLines: [String] {
    [
      "Keyboard",
      "",
      "↑/k  ↓/j     Move selection",
      "←/h  →/l     Switch panel",
      "Tab           Switch panel",
      "Enter         Run action",
      "o             Open deep link",
      "b             Boot selected device",
      "x             Shut down selected device",
      "i             Install .app bundle",
      "L             Launch app by bundle ID",
      "t             Terminate app by bundle ID",
      "s             Take screenshot",
      "c             Copy text to simulator",
      "g             Set simulator location",
      "r             Refresh devices",
      "?             Toggle this help",
      "q             Quit",
      "",
      "All actions operate on the highlighted",
      "simulator. Shutdown devices must be",
      "booted before most actions can run.",
    ]
  }

  private func outputLines(state: TUIState) -> [String] {
    var lines = [String]()
    if let device = state.selectedDevice {
      lines += [
        device.name,
        device.runtimeName,
        device.state,
        device.udid,
        "",
      ]
    }
    lines +=
      state.output.isEmpty
      ? ["Choose an action and press Enter.", "Press ? for keyboard help."]
      : state.output
    return lines
  }

  private func box(
    title: String,
    width: Int,
    height: Int,
    lines: [String],
    selected: Int?,
    focused: Bool
  ) -> [String] {
    let innerWidth = max(1, width - 2)
    let titleText = " \(title) "
    let topFill = max(0, innerWidth - titleText.count)
    let top = "┌" + titleText + String(repeating: "─", count: topFill) + "┐"
    let bottom = "└" + String(repeating: "─", count: innerWidth) + "┘"
    var result = [focused ? style(top, .cyan) : top]

    let contentHeight = max(0, height - 2)
    let scrollOffset: Int
    if let selected, selected >= contentHeight {
      scrollOffset = selected - contentHeight + 1
    } else {
      scrollOffset = 0
    }

    for row in 0..<contentHeight {
      let lineIndex = row + scrollOffset
      let raw = lineIndex < lines.count ? lines[lineIndex] : ""
      let clipped = truncate(raw, width: innerWidth)
      let padded = clipped.padding(toLength: innerWidth, withPad: " ", startingAt: 0)
      let content =
        selected == lineIndex ? style(padded, focused ? .selected : .dimSelected) : padded
      let border = focused ? style("│", .cyan) : "│"
      result.append(border + content + border)
    }
    result.append(focused ? style(bottom, .cyan) : bottom)
    return result
  }

  private func truncate(_ value: String, width: Int) -> String {
    guard width > 0 else { return "" }
    guard value.count > width else { return value }
    guard width > 1 else { return String(value.prefix(width)) }
    return String(value.prefix(width - 1)) + "…"
  }

  private enum Style {
    case boldCyan
    case boldYellow
    case cyan
    case selected
    case dimSelected
    case dim
  }

  private func style(_ value: String, _ style: Style) -> String {
    let code: String
    switch style {
    case .boldCyan: code = "1;36"
    case .boldYellow: code = "1;33"
    case .cyan: code = "36"
    case .selected: code = "30;46"
    case .dimSelected: code = "7;2"
    case .dim: code = "2"
    }
    return "\u{001B}[\(code)m\(value)\u{001B}[0m"
  }
}
