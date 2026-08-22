# SimctlBuddy

`simbuddy` is a Lazygit-style terminal UI for iOS Simulator. Pick a simulator on
the left, choose an action in the middle, and see device details or results on
the right—without remembering `xcrun simctl` commands.

It uses Apple's public `simctl` command—no private frameworks, background daemon,
or accessibility permissions.

```text
 SIMCTLBUDDY   iOS Simulator control deck
┌ Devices ───────────────┐┌ Actions ───────────────┐┌ Details / Output ─────┐
│● iPhone 17 Pro         ││Open deep link       [o]││iPhone 17 Pro           │
│○ iPhone 16             ││Boot / show          [b]││iOS 26.0 · Booted       │
│○ iPad Pro 11-inch      ││Take screenshot      [s]││✓ Deep link opened      │
└────────────────────────┘└────────────────────────┘└────────────────────────┘
 ↑/k ↓/j navigate · ←/h →/l switch panel · Enter run · ? help · q quit
```

## Highlights

- Full-screen, keyboard-driven terminal UI inspired by Lazygit
- Browse every installed simulator and see its boot state at a glance
- Boot a sensible default iPhone or target a specific device
- Open custom URL schemes and universal links
- Save frequently used deep links under memorable names
- Install, launch, restart, terminate, and list apps
- Capture screenshots and create clean status bars
- Copy text to and read text from the simulator clipboard
- Send APNs payloads, change location and appearance, and manage privacy grants
- Produce JSON device output for scripts and coding agents
- Run `doctor` for actionable Xcode and Simulator diagnostics

## Requirements

- macOS 13 or newer
- Xcode with at least one iOS Simulator runtime
- Swift 6.0 or newer when building from source

## Install from source

```bash
git clone https://github.com/Brkoo/SimctlBuddy.git
cd SimctlBuddy
swift build -c release
install -d ~/.local/bin
install .build/release/simbuddy ~/.local/bin/simbuddy
```

Ensure `~/.local/bin` is on your `PATH`. For zsh:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Generate shell completions if desired:

```bash
simbuddy --generate-completion-script zsh > ~/.zfunc/_simbuddy
```

## Interactive terminal UI

Launch it with no arguments:

```bash
simbuddy
```

The important keys are shown inside the app. Use arrow keys or `h/j/k/l` to
navigate, `Tab` to switch panels, `Enter` to run the highlighted action, `?` for
help, and `q` to quit. Quick actions include:

| Key | Action |
| --- | --- |
| `o` | Open a deep link |
| `b` / `x` | Boot or shut down the selected simulator |
| `i` | Install an `.app` bundle |
| `L` / `t` | Launch or terminate an app by bundle identifier |
| `s` | Take a screenshot |
| `c` | Copy text into the simulator clipboard |
| `g` | Set a latitude and longitude |
| `r` | Refresh devices |

Saved deep-link aliases automatically appear as actions in the middle panel.

## Command mode

The original commands remain available for scripts, shell aliases, and coding
agents:

```bash
# See available devices
simbuddy devices

# Boot a sensible default, or choose by partial name
simbuddy boot
simbuddy boot "17 Pro"

# Open a deep link on the booted simulator
simbuddy open 'myapp://profile/42?source=terminal'

# Save routes you use frequently
simbuddy links add login 'myapp://login?mode=test'
simbuddy links add checkout 'myapp://checkout'
simbuddy links run login
simbuddy links list

# Target a particular booted simulator when needed
simbuddy open 'myapp://debug' --device 'iPhone 17 Pro'
```

## Everyday commands

### Apps

```bash
simbuddy install ./Build/MyApp.app
simbuddy launch com.example.MyApp
simbuddy launch com.example.MyApp --restart -- --uitesting --skip-onboarding
simbuddy terminate com.example.MyApp
simbuddy apps
```

Arguments after `--` in `launch` are forwarded to the app.

### Screenshots and status bar

```bash
simbuddy statusbar clean
simbuddy screenshot screenshots/login.png
simbuddy statusbar clear
```

### Clipboard

```bash
simbuddy clipboard copy 'test@example.com'
simbuddy clipboard paste
```

### Push notifications

```bash
simbuddy push com.example.MyApp ./Fixtures/message.apns
```

An example payload:

```json
{
  "Simulator Target Bundle": "com.example.MyApp",
  "aps": {
    "alert": "Hello from SimctlBuddy",
    "sound": "default"
  }
}
```

### Location, appearance, and privacy

```bash
simbuddy location set 46.0569 14.5058
simbuddy location clear
simbuddy appearance dark
simbuddy privacy grant camera com.example.MyApp
simbuddy privacy revoke photos com.example.MyApp
simbuddy privacy reset --service camera com.example.MyApp
```

### Diagnostics and scripting

```bash
simbuddy doctor
simbuddy devices --booted
simbuddy devices --json
```

Run `simbuddy --help` for the complete command list and
`simbuddy help <command>` for every option accepted by a command. You can also
launch the terminal UI explicitly with `simbuddy tui`.

## Device selection

Commands default to the only booted simulator. Pass `--device` (`-d`) when more
than one simulator is booted or when you want a specific target:

```bash
simbuddy screenshot -d 'iPhone 17 Pro'
simbuddy screenshot -d AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
```

Partial names are accepted when they identify exactly one device. Ambiguous
matches produce a list rather than silently choosing the wrong simulator.

## Safety

SimctlBuddy intentionally does not include simulator deletion or erase commands
in its first release. Commands that change app data or privacy settings always
require an explicit bundle identifier.

## Development

```bash
swift test
swift run simbuddy --help
swift run simbuddy doctor
```

The project separates simulator operations, terminal rendering, and command
parsing into independently testable modules.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

SimctlBuddy is available under the [MIT License](LICENSE).
