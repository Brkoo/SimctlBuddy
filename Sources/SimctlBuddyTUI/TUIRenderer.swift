import Foundation
import SimctlBuddyCore

public struct TUIRenderer: Sendable {
  public init() {}

  public func render(state: TUIState, columns: Int, rows: Int) -> String {
    guard columns >= 78, rows >= 18 else {
      return
        "\u{001B}[H\u{001B}[2JSimctlBuddy needs a terminal of at least 78×18. Current size: \(columns)×\(rows)"
    }

    let bodyHeight = rows - 4
    var lines = headerLines(state: state, columns: columns)

    if state.showingHelp {
      lines += box(
        title: "Help",
        width: columns,
        height: bodyHeight,
        lines: helpLines,
        selected: nil,
        focused: true
      )
    } else {
      lines += bodyLines(state: state, columns: columns, available: bodyHeight)
    }

    lines += footerLines(state: state, columns: columns)

    var screen = "\u{001B}[H" + lines.prefix(rows).joined(separator: "\r\n") + "\u{001B}[J"
    if let picker = state.picker {
      screen += pickerOverlay(picker: picker, columns: columns, rows: rows)
    } else if let prompt = state.prompt {
      screen += promptOverlay(prompt: prompt, columns: columns, rows: rows)
    }
    return screen
  }

  // MARK: - Regions

  private func headerLines(state: TUIState, columns: Int) -> [String] {
    let brand = " SIMCTLBUDDY  ·  iOS Simulator control deck"
    let bar = brand.padding(toLength: max(brand.count, columns), withPad: " ", startingAt: 0)
    var result = [style(String(bar.prefix(columns)), .bar)]

    let booted = state.devices.filter(\.isBooted).count
    var chips = [Segment]()
    if let device = state.selectedDevice {
      chips += [
        Segment(" ", nil),
        Segment(device.isBooted ? "●" : "○", device.isBooted ? .boldGreen : .dim),
        Segment(" \(device.name)", .bold),
        Segment("  \(device.runtimeName)", .dim),
        Segment("  \(device.state)", device.isBooted ? .green : .dim),
      ]
    } else {
      chips.append(Segment(" No simulator selected", .dim))
    }
    let tally = "\(modeName(state.screenMode)) · \(booted) booted · \(state.devices.count) total "
    let used = Line(segments: chips).plain.count
    let gap = max(1, columns - used - tally.count)
    chips.append(Segment(String(repeating: " ", count: gap), nil))
    chips.append(Segment(tally, .dim))
    result.append(compose(Line(segments: chips), width: columns))
    return result
  }

  /// Keeps as many key hints as fit, separated by middots.
  private func fittedHints(_ hints: [(String, String)], width: Int) -> [Segment] {
    var segments = [Segment]()
    var used = 0
    for (key, label) in hints {
      let separator = segments.isEmpty ? "" : " · "
      let cost = separator.count + key.count + 1 + label.count
      guard used + cost <= width else { break }
      if !separator.isEmpty { segments.append(Segment(separator, .dim)) }
      segments.append(Segment(key, .key))
      segments.append(Segment(" \(label)", .dim))
      used += cost
    }
    return segments
  }

  private func deviceTitle(state: TUIState) -> String {
    let total = state.devices.count
    guard !state.deviceFilter.isEmpty else { return "Devices \(total)" }
    return "Devices \(state.visibleDevices.count)/\(total) · /\(state.deviceFilter)"
  }

  private func actionTitle(state: TUIState) -> String {
    guard !state.actionFilter.isEmpty else { return "Actions" }
    return "Actions \(state.visibleActions.count)/\(state.actions.count) · /\(state.actionFilter)"
  }

  private func modeName(_ mode: TUIScreenMode) -> String {
    switch mode {
    case .normal: return "normal"
    case .half: return "half"
    case .full: return "full"
    }
  }

  private func bodyLines(state: TUIState, columns: Int, available: Int) -> [String] {
    let devices = deviceLines(state: state)
    let details = detailLines(state: state)

    if state.screenMode == .full {
      // Full mode hands the whole window to the focused panel.
      switch state.focus {
      case .devices:
        let listHeight = min(max(3, devices.count + 2), max(5, available - 5))
        return box(
          title: deviceTitle(state: state),
          width: columns,
          height: listHeight,
          lines: devices,
          selected: state.selectedDeviceIndex,
          focused: true
        )
          + box(
            title: "Details",
            width: columns,
            height: available - listHeight,
            lines: details,
            selected: nil,
            focused: false
          )
      case .actions:
        let (menu, menuSelection) = actionMenu(state: state, width: columns - 2)
        return box(
          title: actionTitle(state: state),
          width: columns,
          height: available,
          lines: menu,
          selected: menuSelection,
          focused: true
        )
      }
    }

    let (deviceWidth, actionWidth) = panelWidths(state: state, columns: columns)
    let logWidth = columns - deviceWidth - actionWidth
    let log = logLines(state: state, width: logWidth - 2)

    // Panels fill the window; the left column gives the device list only what it
    // needs so the details card absorbs the leftover height.
    let height = available
    let listHeight = min(max(3, devices.count + 2), max(5, height - 5))
    let cardHeight = height - listHeight

    let deviceBox = box(
      title: deviceTitle(state: state),
      width: deviceWidth,
      height: listHeight,
      lines: devices,
      selected: state.selectedDeviceIndex,
      focused: state.focus == .devices
    )
    let cardBox = box(
      title: "Details",
      width: deviceWidth,
      height: cardHeight,
      lines: details,
      selected: nil,
      focused: false
    )
    let (sizedMenu, sizedSelection) = actionMenu(state: state, width: actionWidth - 2)
    let actionBox = box(
      title: actionTitle(state: state),
      width: actionWidth,
      height: height,
      lines: sizedMenu,
      selected: sizedSelection,
      focused: state.focus == .actions
    )
    let logBox = box(
      title: "Activity",
      width: logWidth,
      height: height,
      lines: log,
      selected: nil,
      focused: false
    )

    let left = deviceBox + cardBox
    return (0..<height).map { left[$0] + actionBox[$0] + logBox[$0] }
  }

  /// Splits the window between the three columns for the current screen mode,
  /// always leaving the activity panel a usable width.
  private func panelWidths(state: TUIState, columns: Int) -> (Int, Int) {
    let minimum = 16
    var deviceWidth: Int
    var actionWidth: Int

    switch (state.screenMode, state.focus) {
    case (.half, .devices):
      deviceWidth = columns / 2
      actionWidth = max(minimum, (columns - deviceWidth) * 45 / 100)
    case (.half, .actions):
      actionWidth = columns / 2
      deviceWidth = max(minimum, (columns - actionWidth) * 45 / 100)
    default:
      deviceWidth = min(34, max(26, columns * 26 / 100))
      actionWidth = min(40, max(30, columns * 30 / 100))
    }

    // Shave the widest column until the activity panel fits.
    while columns - deviceWidth - actionWidth < minimum {
      if deviceWidth >= actionWidth {
        deviceWidth -= 1
      } else {
        actionWidth -= 1
      }
    }
    return (deviceWidth, actionWidth)
  }

  private func footerLines(state: TUIState, columns: Int) -> [String] {
    if state.picker != nil {
      return [
        compose(
          Line(segments: [
            Segment(" ", nil),
            Segment("Pick an app", .boldYellow), Segment(" · ", .dim),
            Segment("type", .key), Segment(" to search · ", .dim),
            Segment("Tab", .key), Segment(" enter one by hand", .dim),
          ]), width: columns),
        compose(
          Line(segments: [Segment(" Saved apps are listed first", .dim)]), width: columns),
      ]
    }

    if let prompt = state.prompt {
      if prompt.kind.isConfirmation {
        return [
          compose(
            Line(segments: [
              Segment(" ", nil),
              Segment("Confirm", .boldYellow), Segment(" · ", .dim),
              Segment("Enter", .key), Segment(" yes · ", .dim),
              Segment("Esc", .key), Segment(" no", .dim),
            ]), width: columns),
          compose(
            Line(segments: [Segment(" Nothing happens until you press Enter", .dim)]),
            width: columns),
        ]
      }
      return [
        compose(
          Line(segments: [
            Segment(" ", nil),
            Segment("Dialog open", .boldYellow),
            Segment(" · ", .dim),
            Segment("Enter", .key), Segment(" confirm · ", .dim),
            Segment("Esc", .key), Segment(" cancel", .dim),
          ]), width: columns),
        compose(
          Line(segments: [
            Segment(" Type normally · Backspace deletes · Ctrl+U clears", .dim)
          ]), width: columns),
      ]
    }
    if state.filtering {
      let query = state.activeFilter
      let target = state.focus == .devices ? "devices" : "actions"
      return [
        compose(
          Line(segments: [
            Segment(" /", .boldCyan), Segment(query, nil), Segment("▌", .boldCyan),
            Segment("   filtering \(target)", .dim),
          ]), width: columns),
        compose(
          Line(segments: [
            Segment(" ", nil),
            Segment("Enter", .key), Segment(" accept · ", .dim),
            Segment("Esc", .key), Segment(" clear · ", .dim),
            Segment("↑/↓", .key), Segment(" move · ", .dim),
            Segment("Ctrl+U", .key), Segment(" wipe", .dim),
          ]), width: columns),
      ]
    }

    // Hints are dropped from the end when the window is too narrow, so the
    // footer never wraps and breaks the layout.
    let hints = [
      ("↑/k ↓/j", "move"),
      ("←/h →/l", "panel"),
      ("Enter", "run"),
      ("/", "filter"),
      ("+/-", "size"),
      ("o", "link"),
      ("r", "refresh"),
    ]
    let nav = Line(segments: [Segment(" ", nil)] + fittedHints(hints, width: columns - 1))
    let meta = Line(segments: [
      Segment(" ", nil),
      Segment("q", .key), Segment(" quit · ", .dim),
      Segment("?", .key), Segment(" help   ", .dim),
      Segment("Actions target the selected simulator", .dim),
    ])
    return [compose(nav, width: columns), compose(meta, width: columns)]
  }

  // MARK: - Panel content

  private func deviceLines(state: TUIState) -> [Line] {
    let visible = state.visibleDevices
    guard !visible.isEmpty else {
      if !state.deviceFilter.isEmpty {
        return [Line(segments: [Segment("No devices match /\(state.deviceFilter)", .dim)])]
      }
      return [
        Line(segments: [Segment("No simulators found", .dim)]),
        Line(segments: [Segment("Run doctor for diagnostics", .dim)]),
      ]
    }
    return visible.map { device in
      Line(segments: [
        Segment(device.isBooted ? "● " : "○ ", device.isBooted ? .boldGreen : .dim),
        Segment(device.name, device.isBooted ? .bold : nil),
        Segment("  \(device.runtimeName)", .dim),
      ])
    }
  }

  private func detailLines(state: TUIState) -> [Line] {
    var lines = [Line]()
    if state.selectedDevice == nil {
      lines.append(Line(segments: [Segment("No simulator selected", .dim)]))
    }
    if let device = state.selectedDevice {
      lines += [
        Line(segments: [Segment(device.name, .bold)]),
        Line(segments: [Segment(device.runtimeName, .dim)]),
        Line(segments: [
          Segment(device.isBooted ? "● " : "○ ", device.isBooted ? .boldGreen : .dim),
          Segment(device.state, device.isBooted ? .green : .dim),
        ]),
        Line(segments: [Segment(device.udid, .dim)]),
        Line(segments: []),
      ]
    }
    if case .savedLink(let link) = state.selectedAction?.id {
      lines += [
        Line(segments: [Segment("SAVED LINK", .section)]),
        Line(segments: [Segment(link.name, .bold)]),
        Line(segments: [Segment(link.url, .magenta)]),
        Line(segments: []),
        Line(segments: [
          Segment("↵", .key), Segment(" Press Enter to open it.", .dim),
        ]),
        Line(segments: [
          Segment("e", .key), Segment(" Press e to edit its URL.", .dim),
        ]),
        Line(segments: [
          Segment("d", .key), Segment(" Press d to delete it.", .dim),
        ]),
      ]
    }
    return lines
  }

  private static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  private func logLines(state: TUIState, width: Int) -> [Line] {
    var lines = [Line]()
    if let busy = state.busy {
      let frame = Self.spinnerFrames[
        abs(state.spinnerFrame) % Self.spinnerFrames.count]
      lines.append(
        Line(segments: [
          Segment("\(frame) ", .boldYellow), Segment("\(busy)…", .yellow),
        ]))
      lines.append(Line(segments: []))
    }
    guard !state.output.isEmpty else {
      return lines
        + [
          Line(segments: [Segment("Choose an action and press Enter.", .dim)]),
          Line(segments: [Segment("Press ? for keyboard help.", .dim)]),
        ]
    }
    return lines + state.output.flatMap { entry -> [Line] in
      let entryStyle: Style
      if entry.hasPrefix("✗") {
        entryStyle = .red
      } else if entry.hasPrefix("  ") {
        entryStyle = .dim
      } else {
        entryStyle = .green
      }
      // Wrapping keeps long deep links readable instead of clipping them.
      return wrap(entry, width: width).map { chunk in
        Line(segments: [Segment(chunk, entryStyle)])
      }
    }
  }

  /// Wraps on word boundaries, preserving the entry's own indent and indenting
  /// continuation rows two columns further so blocks stay readable.
  private func wrap(_ value: String, width: Int) -> [String] {
    let body = value.drop(while: { $0 == " " })
    let indent = String(repeating: " ", count: value.count - body.count)
    let bodyWidth = max(4, width - indent.count)
    guard width > 4, body.count > bodyWidth else { return [value] }

    var chunks = [String]()
    var current = ""
    var limit = bodyWidth
    for word in body.split(separator: " ") {
      let candidate = current.isEmpty ? String(word) : current + " " + word
      if candidate.count <= limit {
        current = candidate
        continue
      }
      if !current.isEmpty {
        chunks.append(current)
        limit = bodyWidth - 2
      }
      var rest = String(word)
      while rest.count > limit {
        chunks.append(String(rest.prefix(limit)))
        rest = String(rest.dropFirst(limit))
        limit = bodyWidth - 2
      }
      current = rest
    }
    if !current.isEmpty { chunks.append(current) }
    guard !chunks.isEmpty else { return [value] }

    return chunks.enumerated().map { index, chunk in
      index == 0 ? indent + chunk : indent + "  " + chunk
    }
  }

  /// Builds the action menu with rule-style section headers, returning the
  /// display row of the selected action so headers never steal the selection.
  private func actionMenu(state: TUIState, width: Int) -> ([Line], Int?) {
    var lines = [Line]()
    var selectedRow: Int?
    var currentSection: String?

    let visible = state.visibleActions
    guard !visible.isEmpty else {
      return ([Line(segments: [Segment("No actions match /\(state.actionFilter)", .dim)])], nil)
    }

    for (index, action) in visible.enumerated() {
      let section = sectionTitle(for: action.id)
      if section != currentSection {
        let fill = max(1, width - section.count - 1)
        lines.append(
          Line(segments: [
            Segment(section, .section),
            Segment(" " + String(repeating: "─", count: fill), .border),
          ]))
        currentSection = section
      }
      if index == state.selectedActionIndex { selectedRow = lines.count }
      var segments = [Segment(" \(action.title)", nil)]
      if !action.hint.isEmpty {
        segments.append(Segment("  [\(action.hint)]", .key))
      }
      lines.append(Line(segments: segments))
    }
    return (lines, selectedRow)
  }

  private func sectionTitle(for id: TUIActionID) -> String {
    switch id {
    case .openDeepLink, .addSavedLink, .savedLink: return "LINKS"
    case .savedApp, .saveApp: return "SAVED APPS"
    case .boot, .shutdown: return "DEVICE"
    case .installApp, .launchApp, .terminateApp, .listApps, .push: return "APPS"
    case .privacy, .privacyReset: return "PRIVACY"
    case .screenshot, .clipboard, .clipboardPaste, .location, .locationClear: return "CAPTURE"
    case .appearanceDark, .appearanceLight, .cleanStatusBar, .clearStatusBar: return "APPEARANCE"
    case .doctor, .refresh: return "SYSTEM"
    }
  }

  private var helpLines: [Line] {
    let shortcuts: [(String, String)] = [
      ("↑/k  ↓/j", "Move selection"),
      ("←/h  →/l", "Switch panel"),
      ("Tab", "Switch panel"),
      ("+  -", "Grow / shrink the focused panel"),
      ("/", "Filter the focused panel"),
      ("Enter", "Run action"),
      ("o", "Open deep link"),
      ("a", "Add saved deep link"),
      ("e", "Edit highlighted saved link"),
      ("d", "Delete highlighted saved link or app"),
      ("p", "Send a push notification"),
      ("v", "Read the simulator clipboard"),
      ("b", "Boot selected device"),
      ("x", "Shut down selected device"),
      ("i", "Install .app bundle"),
      ("L", "Launch app by bundle ID"),
      ("t", "Terminate app by bundle ID"),
      ("s", "Take screenshot"),
      ("c", "Copy text to simulator"),
      ("g", "Set simulator location"),
      ("r", "Refresh devices"),
      ("?", "Toggle this help"),
      ("q", "Quit"),
    ]
    var lines = [
      Line(segments: [Segment("KEYBOARD", .section)]),
      Line(segments: []),
    ]
    lines += shortcuts.map { key, label in
      let padded = " \(key)".padding(toLength: 14, withPad: " ", startingAt: 0)
      return Line(segments: [Segment(padded, .key), Segment(label, nil)])
    }
    lines += [
      Line(segments: []),
      Line(segments: [
        Segment(
          " All actions operate on the highlighted simulator. Shut down devices must be "
            + "booted before most actions can run.", .dim)
      ]),
    ]
    return lines
  }

  // MARK: - Dialog

  private func promptOverlay(prompt: TUIPrompt, columns: Int, rows: Int) -> String {
    let width = min(72, max(50, columns * 2 / 3))
    let height = 9
    let inputWidth = width - 6
    let input: String
    if prompt.value.isEmpty {
      input = "▌"
    } else {
      let visible = String(prompt.value.suffix(max(1, inputWidth - 1)))
      input = visible + "▌"
    }

    var body: [Line] = [
      Line(segments: []),
      Line(segments: [Segment(" \(prompt.label)", .bold)]),
    ]
    if prompt.kind.isConfirmation {
      body += [
        Line(segments: []),
        Line(segments: [Segment(" This cannot be undone.", .dim)]),
        Line(segments: []),
        Line(segments: [
          Segment(" Enter", .key), Segment(" delete  ·  ", .dim),
          Segment("Esc", .key), Segment(" keep it", .dim),
        ]),
        Line(segments: []),
      ]
    } else {
      body += [
        Line(segments: [Segment(" › ", .boldCyan), Segment(input, nil)]),
        Line(segments: [Segment(" Example: \(promptPlaceholder(for: prompt.kind))", .dim)]),
        Line(segments: []),
        Line(segments: [
          Segment(" Enter", .key), Segment(" confirm  ·  ", .dim),
          Segment("Ctrl+U", .key), Segment(" clear  ·  ", .dim),
          Segment("Esc", .key), Segment(" cancel", .dim),
        ]),
        Line(segments: []),
      ]
    }

    let dialog = box(
      title: promptTitle(for: prompt.kind),
      width: width,
      height: height,
      lines: body,
      selected: nil,
      focused: true
    )
    let top = max(3, (rows - height) / 2 + 1)
    let left = max(1, (columns - width) / 2 + 1)

    return dialog.enumerated().map { index, line in
      "\u{001B}[\(top + index);\(left)H\(line)"
    }.joined()
  }

  private func pickerOverlay(picker: TUIPicker, columns: Int, rows: Int) -> String {
    let width = min(76, max(52, columns * 2 / 3))
    let visible = picker.visibleOptions
    let listHeight = max(1, min(10, visible.count))
    let height = listHeight + 7

    var body: [Line] = [
      Line(segments: [
        Segment(" /", .boldCyan), Segment(picker.query, nil), Segment("▌", .boldCyan),
      ]),
      Line(segments: []),
    ]

    if visible.isEmpty {
      body.append(
        Line(segments: [
          Segment(
            picker.isLoading ? " Reading installed apps…" : " No apps match this search", .dim)
        ]))
    } else {
      // Keep the highlighted row on screen for long app lists.
      let offset = max(0, min(picker.selectedIndex - listHeight + 1, visible.count - listHeight))
      for row in 0..<listHeight {
        let index = row + offset
        guard visible.indices.contains(index) else { break }
        let option = visible[index]
        let marker = index == picker.selectedIndex ? "❯ " : "  "
        var segments = [
          Segment(marker, index == picker.selectedIndex ? .boldCyan : nil),
          Segment(option.label, index == picker.selectedIndex ? .bold : nil),
        ]
        if option.detail != option.label {
          segments.append(Segment("  \(option.detail)", .dim))
        }
        body.append(Line(segments: segments))
      }
    }

    body += [
      Line(segments: []),
      Line(segments: [
        Segment(" ↑/↓", .key), Segment(" move · ", .dim),
        Segment("Enter", .key), Segment(" choose · ", .dim),
        Segment("Tab", .key), Segment(" type it · ", .dim),
        Segment("Esc", .key), Segment(" cancel", .dim),
      ]),
    ]
    if picker.isLoading && !visible.isEmpty {
      body.append(Line(segments: [Segment(" Still reading installed apps…", .dim)]))
    }

    let dialog = box(
      title: picker.title,
      width: width,
      height: height,
      lines: body,
      selected: nil,
      focused: true
    )
    let top = max(2, (rows - height) / 2 + 1)
    let left = max(1, (columns - width) / 2 + 1)
    return dialog.enumerated().map { index, line in
      "\u{001B}[\(top + index);\(left)H\(line)"
    }.joined()
  }

  private func promptTitle(for kind: TUIPromptKind) -> String {
    switch kind {
    case .deepLink: return "Open deep link"
    case .savedLinkName: return "Save deep link · 1 of 2"
    case .savedLinkURL: return "Save deep link · 2 of 2"
    case .editSavedLinkURL: return "Edit saved deep link"
    case .installApp: return "Install app"
    case .launchApp: return "Launch app"
    case .terminateApp: return "Terminate app"
    case .clipboard: return "Copy to simulator"
    case .location: return "Set location"
    case .pushBundle: return "Send push · 1 of 2"
    case .pushPayload: return "Send push · 2 of 2"
    case .privacyService(let action): return "\(action.rawValue.capitalized) privacy · 1 of 2"
    case .privacyBundle(let action, _): return "\(action.rawValue.capitalized) privacy · 2 of 2"
    case .privacyResetBundle: return "Reset privacy permissions"
    case .confirmRemoveSavedLink: return "Delete saved deep link"
    case .savedAppName: return "Save app · name it"
    case .editSavedAppBundle(let name): return "Edit \(name)"
    case .confirmRemoveSavedApp: return "Delete saved app"
    }
  }

  private func promptPlaceholder(for kind: TUIPromptKind) -> String {
    switch kind {
    case .deepLink: return "myapp://profile/42"
    case .savedLinkName: return "login"
    case .savedLinkURL, .editSavedLinkURL: return "myapp://login"
    case .installApp: return "/path/to/MyApp.app"
    case .launchApp, .terminateApp: return "com.example.MyApp"
    case .clipboard: return "Text copied into the simulator"
    case .location: return "46.0569,14.5058"
    case .pushBundle, .privacyBundle, .privacyResetBundle: return "com.example.MyApp"
    case .pushPayload: return "~/payloads/welcome.apns"
    case .privacyService: return "photos, camera, microphone, contacts, location"
    case .confirmRemoveSavedLink, .confirmRemoveSavedApp: return ""
    case .savedAppName: return "Checkout build"
    case .editSavedAppBundle: return "com.example.MyApp"
    }
  }

  // MARK: - Box drawing

  private func box(
    title: String,
    width: Int,
    height: Int,
    lines: [Line],
    selected: Int?,
    focused: Bool
  ) -> [String] {
    let innerWidth = max(1, width - 2)
    let borderStyle: Style = focused ? .borderFocus : .border
    let titleText = " \(title) "
    let topFill = max(0, innerWidth - titleText.count)
    let top =
      style("┌", borderStyle) + style(String(titleText.prefix(innerWidth)), focused ? .boldCyan : .title)
      + style(String(repeating: "─", count: topFill), borderStyle) + style("┐", borderStyle)
    let bottom = style("└" + String(repeating: "─", count: innerWidth) + "┘", borderStyle)
    var result = [top]

    let contentHeight = max(0, height - 2)
    let scrollOffset: Int
    if let selected, selected >= contentHeight {
      scrollOffset = selected - contentHeight + 1
    } else {
      scrollOffset = 0
    }

    for row in 0..<contentHeight {
      let lineIndex = row + scrollOffset
      let line = lineIndex < lines.count ? lines[lineIndex] : Line(segments: [])
      let content: String
      if selected == lineIndex {
        let padded = pad(truncate(line.plain, width: innerWidth), width: innerWidth)
        content = style(padded, focused ? .selected : .dimSelected)
      } else {
        content = compose(line, width: innerWidth)
      }
      let border = style("│", borderStyle)
      result.append(border + content + border)
    }
    result.append(bottom)
    return result
  }

  /// Renders a line's segments, clipping and padding on plain text so ANSI
  /// escapes never count toward the column budget.
  private func compose(_ line: Line, width: Int?) -> String {
    var remaining = width ?? Int.max
    var rendered = ""
    var used = 0

    for segment in line.segments {
      guard remaining > 0 else { break }
      let text: String
      if segment.text.count > remaining {
        text = truncate(segment.text, width: remaining)
      } else {
        text = segment.text
      }
      guard !text.isEmpty else { continue }
      rendered += segment.style.map { style(text, $0) } ?? text
      used += text.count
      remaining -= text.count
    }

    guard let width else { return rendered }
    return rendered + String(repeating: " ", count: max(0, width - used))
  }

  private func pad(_ value: String, width: Int) -> String {
    value + String(repeating: " ", count: max(0, width - value.count))
  }

  private func truncate(_ value: String, width: Int) -> String {
    guard width > 0 else { return "" }
    guard value.count > width else { return value }
    guard width > 1 else { return String(value.prefix(width)) }
    return String(value.prefix(width - 1)) + "…"
  }

  // MARK: - Styling

  private struct Segment {
    let text: String
    let style: Style?

    init(_ text: String, _ style: Style?) {
      self.text = text
      self.style = style
    }
  }

  private struct Line {
    var segments: [Segment]
    var plain: String { segments.map(\.text).joined() }
  }

  private enum Style {
    case bar
    case bold
    case boldCyan
    case boldGreen
    case boldYellow
    case border
    case borderFocus
    case dim
    case dimSelected
    case green
    case key
    case magenta
    case red
    case section
    case selected
    case title
    case yellow
  }

  private func style(_ value: String, _ style: Style) -> String {
    let code: String
    switch style {
    case .bar: code = "1;7;36"
    case .bold: code = "1"
    case .boldCyan: code = "1;36"
    case .boldGreen: code = "1;32"
    case .boldYellow: code = "1;33"
    case .border: code = "90"
    case .borderFocus: code = "1;36"
    case .dim: code = "2"
    case .dimSelected: code = "7;2"
    case .green: code = "32"
    case .key: code = "33"
    case .magenta: code = "35"
    case .red: code = "31"
    case .section: code = "1;35"
    case .selected: code = "30;46"
    case .title: code = "1"
    case .yellow: code = "33"
    }
    return "\u{001B}[\(code)m\(value)\u{001B}[0m"
  }
}
