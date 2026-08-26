# SimctlBuddy

`simbuddy` is a Lazygit-style terminal UI for iOS Simulator. Pick a simulator on
the left, choose an action in the middle, and see device details or results on
the right—without remembering `xcrun simctl` commands.

It uses Apple's public `simctl` command—no private frameworks, background daemon,
or accessibility permissions.

```text
 SIMCTLBUDDY  ·  iOS Simulator control deck
 ● iPhone 17 Pro  iOS 26.5  Booted                     2 booted · 9 total
┌ Devices 9 ─────────────┐┌ Actions ───────────────┐┌ Activity ──────────────┐
│● iPhone 17 Pro  iOS 26…││LINKS ──────────────────││✓ Opened Purchase popup │
│○ iPhone 16  iOS 26.0   ││ Open deep link  [o]    ││  → myapp://purchase    │
│○ iPad Pro 11  iOS 26.5 ││ ↗ Purchase popup  [↵/e]││✓ Screenshot saved      │
└────────────────────────┘│DEVICE ─────────────────││✗ iPhone 16 is shut     │
┌ Details ───────────────┐│ Boot / show  [b]       ││  down. Boot it first.  │
│iPhone 17 Pro           ││ Shut down  [x]         ││                        │
│● Booted                ││CAPTURE ────────────────││                        │
│↗ myapp://purchase      ││ Take screenshot  [s]   ││                        │
└────────────────────────┘└────────────────────────┘└────────────────────────┘
 ↑/k ↓/j move · ←/h →/l panel · Enter run · +/- size · o link · r refresh
 q quit · ? help   Actions target the selected simulator
```

## Highlights

- Full-screen, keyboard-driven terminal UI inspired by Lazygit
- Grow the focused panel with `+` and shrink it with `-` (normal, half, full)
- Filter simulators and saved deep links with `/`
- Long commands run in the background with a spinner instead of freezing
- Browse every installed simulator and see its boot state at a glance
- Boot a sensible default iPhone or target a specific device
- Open custom URL schemes and universal links
- Save frequently used deep links under memorable names
- Pick app bundle identifiers from the apps installed on the simulator
- Save bundle identifiers under names and launch them with one key
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
| `a` | Add or update a saved deep link |
| `e` | Edit the highlighted saved link |
| `b` / `x` | Boot or shut down the selected simulator |
| `i` | Install an `.app` bundle |
| `s` | Take a screenshot |
| `c` | Copy text into the simulator clipboard |
| `g` | Set a latitude and longitude |
| `r` | Refresh devices |
| `p` | Send a push notification |
| `L` / `t` | Launch or terminate — pick the app from a list |
| `v` | Read the simulator clipboard |
| `d` | Delete the highlighted saved link |
| `+` / `-` | Grow or shrink the focused panel |
| `/` | Filter the focused panel |
| `Ctrl+C` | Quit |

Actions that need an app no longer ask you to remember a bundle identifier.
Launch, terminate, push, and the privacy actions open a searchable list of the
apps installed on the selected simulator, with your saved apps at the top. Type
to narrow it, `Enter` to choose, or `Tab` to type an identifier by hand for an
app that is not installed yet.

Choose **Save app bundle ID** to remember an app under a short name. Saved apps
appear in their own section: `Enter` launches one, `e` edits its identifier, and
`d` deletes it. They are stored in `~/.config/simbuddy/apps.json` and are also
available from the command line:

```bash
simbuddy bundles add checkout com.example.Checkout
simbuddy bundles list
simbuddy bundles remove checkout
```

Press `/` to filter the focused panel. Filtering the device list matches on name
and runtime, so `/mini` or `/18.6` both narrow it. Filtering the actions panel
matches action titles and saved deep-link URLs, so `/bills` finds the link that
points at `myapp://navigate/bills`. `Enter` keeps the filter, `Esc` clears it,
`Ctrl+U` wipes the query, and `Tab` commits it and moves to the other panel.
Each panel remembers its own filter, and the panel title shows the match count.

Long-running commands such as booting a simulator or installing an app run in
the background with a spinner in the activity panel, so the interface stays
responsive and you can keep navigating while they finish.

Press `+` to give the focused panel more room and `-` to give it back, cycling
through three screen modes like Lazygit: `normal` splits the window three ways,
`half` gives the focused panel half the width, and `full` hands it the whole
window. The status bar shows which mode is active. Note that `full` hides the
activity panel, so switch back to see command output.

Deep links and other text inputs open in a centered dialog. Saved deep-link
aliases automatically appear as actions in the middle panel; press `a` to add
one without leaving the interface. Highlight a saved link and press `e` to edit
its current URL. The edit dialog is prefilled; press `Ctrl+U` to clear it quickly.

## Command mode

Everything the command line can do is also reachable from the interactive UI,
including push notifications, privacy permissions, and diagnostics. The command
line remains the way to script SimctlBuddy — a terminal interface cannot be piped
into `jq` or run from CI.

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
