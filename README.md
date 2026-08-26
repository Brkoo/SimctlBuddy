<div align="center">

# SimctlBuddy

**A Lazygit-style terminal UI for the iOS Simulator.**

Pick a simulator, choose an action, watch it happen — without remembering a single
`xcrun simctl` incantation.

[![CI](https://github.com/Brkoo/SimctlBuddy/actions/workflows/ci.yml/badge.svg)](https://github.com/Brkoo/SimctlBuddy/actions/workflows/ci.yml)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

```text
 SIMCTLBUDDY  ·  iOS Simulator control deck
 ● iPhone 17 Pro  iOS 26.5  Booted                    normal · 2 booted · 9 total
┌ Devices 9 ─────────────┐┌ Actions ───────────────┐┌ Activity ──────────────┐
│● iPhone 17 Pro  iOS 26…││LINKS ──────────────────││⠹ Booting iPhone 16…    │
│○ iPhone 16  iOS 26.0   ││ Open deep link  [o]    ││                        │
│○ iPad Pro 11  iOS 26.5 ││ ↗ Purchase popup [↵/e…]││✓ Opened Purchase popup │
└────────────────────────┘│SAVED APPS ─────────────││  → myapp://purchase    │
┌ Details ───────────────┐│ ▶ Checkout     [↵/e/d] ││✓ Screenshot saved      │
│iPhone 17 Pro           ││DEVICE ─────────────────││✗ iPhone 16 is shut     │
│● Booted                ││ Boot / show      [b]   ││  down. Boot it first.  │
│↗ myapp://purchase      ││ Shut down        [x]   ││                        │
└────────────────────────┘└────────────────────────┘└────────────────────────┘
 ↑/k ↓/j move · ←/h →/l panel · Enter run · / filter · +/- size · o link
 q quit · ? help   Actions target the selected simulator
```

## Contents

- [Why](#why)
- [Install](#install)
- [Quick start](#quick-start)
- [The interactive UI](#the-interactive-ui)
- [Scripting](#scripting)
- [Where things are stored](#where-things-are-stored)
- [Requirements](#requirements)
- [Development](#development)

## Why

`xcrun simctl` is powerful and completely unmemorable. Booting a device means
copying a UDID; opening a deep link means retyping the same URL for the fiftieth
time; sending a push means remembering the payload flag order.

SimctlBuddy puts all of it behind a keyboard-driven interface, and remembers the
things you use repeatedly — deep links and app bundle identifiers — under names
you choose.

It shells out to Apple's public `simctl`. No private frameworks, no background
daemon, no accessibility permissions.

**Two ways in, on purpose.** The terminal UI is for working by hand. The
subcommands are for scripts, shell aliases, CI, and coding agents — a terminal UI
cannot be piped into `jq`. Both reach the same features.

## Install

Build from source:

```bash
git clone https://github.com/Brkoo/SimctlBuddy.git
cd SimctlBuddy
swift build -c release
install -d ~/.local/bin
install .build/release/simbuddy ~/.local/bin/simbuddy
```

Make sure `~/.local/bin` is on your `PATH`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

Shell completions are optional:

```bash
simbuddy --generate-completion-script zsh > ~/.zfunc/_simbuddy
```

## Quick start

```bash
simbuddy
```

That opens the UI. Move with `↑`/`↓`, switch panels with `Tab`, run the
highlighted action with `Enter`, and quit with `q`. Press `?` at any time for the
full key list.

If something looks wrong with your Xcode setup, run the diagnostics first:

```bash
simbuddy doctor
```

## The interactive UI

Three panels: simulators on the left over a details card, actions in the middle,
results on the right. Actions always target the highlighted simulator.

### Keys

| Key | Action |
| --- | --- |
| `↑` `↓` / `k` `j` | Move the selection |
| `←` `→` / `h` `l` / `Tab` | Switch panel |
| `Enter` | Run the highlighted action |
| `/` | Filter the focused panel |
| `+` `-` | Grow or shrink the focused panel |
| `?` | Toggle help |
| `q` / `Ctrl+C` | Quit |
| `o` | Open a deep link |
| `a` | Save a deep link |
| `e` | Edit the highlighted saved link or app |
| `d` | Delete the highlighted saved link or app |
| `b` / `x` | Boot or shut down the simulator |
| `i` | Install an `.app` bundle |
| `L` / `t` | Launch or terminate an app |
| `p` | Send a push notification |
| `s` | Take a screenshot |
| `c` / `v` | Copy text to, or read text from, the simulator clipboard |
| `g` | Set a location |
| `r` | Refresh devices |

### Picking apps instead of typing identifiers

Launch, terminate, push, and the privacy actions open a searchable list of the
apps installed on the selected simulator, with your saved apps at the top:

```text
┌ Launch app ───────────────────────────────────────┐
│ /mobile▌                                          │
│                                                   │
│❯ Checkout  com.example.Checkout                   │
│  com.apple.MobileSMS  installed                   │
│  com.apple.mobilecal  installed                   │
│                                                   │
│ ↑/↓ move · Enter choose · Tab type it · Esc cancel│
└───────────────────────────────────────────────────┘
```

Type to narrow the list, `Enter` to choose. `Tab` switches to typing an
identifier by hand, for an app that is not installed yet.

### Saving links and apps

Deep links and bundle identifiers you use repeatedly get names and their own
sections in the actions panel.

- Press `a` to save a deep link, then `Enter` on it to open it.
- Choose **Save app bundle ID** to name an app, then `Enter` on it to launch it.
- On either, `e` edits and `d` deletes. Deletions ask first.

### Filtering

Press `/` to filter the focused panel. Simulators match on name and runtime, so
`/mini` and `/18.6` both narrow the list. Actions match on title, deep-link URL,
and bundle identifier, so `/bills` finds the link pointing at
`myapp://navigate/bills`.

`Enter` keeps the filter, `Esc` clears it, `Ctrl+U` wipes the query, and `Tab`
commits it and moves to the other panel. Each panel remembers its own filter, and
the panel title shows the match count.

### Screen modes

`+` gives the focused panel more room and `-` gives it back, cycling three modes
like Lazygit:

| Mode | Layout |
| --- | --- |
| `normal` | Three columns |
| `half` | Focused panel takes half the width |
| `full` | Focused panel takes the whole window |

The status bar shows the active mode. `full` hides the activity panel, so switch
back to see command output.

### Nothing blocks

Booting a simulator or installing an app runs in the background with a spinner in
the activity panel. The interface stays responsive and you can keep navigating
while it finishes.

## Scripting

Every subcommand defaults to the only booted simulator. Pass `--device` (`-d`)
with a name, partial name, or UDID to target a specific one. Partial names are
accepted when they identify exactly one device; ambiguous matches list the
candidates rather than guessing.

### Devices

```bash
simbuddy devices
simbuddy devices --booted
simbuddy devices --json
simbuddy boot                 # a sensible default iPhone
simbuddy boot "17 Pro"        # or a partial name
simbuddy shutdown
```

### Deep links

```bash
simbuddy open 'myapp://profile/42?source=terminal'
simbuddy open 'myapp://debug' --device 'iPhone 17 Pro'

simbuddy links add login 'myapp://login?mode=test'
simbuddy links run login
simbuddy links list
simbuddy links remove login
```

### Apps

```bash
simbuddy install ./Build/MyApp.app
simbuddy launch com.example.MyApp
simbuddy launch com.example.MyApp --restart -- --uitesting --skip-onboarding
simbuddy terminate com.example.MyApp
simbuddy apps                 # installed apps, as JSON

simbuddy bundles add checkout com.example.Checkout
simbuddy bundles list
simbuddy bundles remove checkout
```

Arguments after `--` in `launch` are forwarded to the app.

### Screenshots and status bar

```bash
simbuddy statusbar clean      # 9:41, full bars, full battery
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

### Diagnostics

```bash
simbuddy doctor
```

Run `simbuddy --help` for the full command list, or `simbuddy help <command>` for
one command's options. `simbuddy tui` opens the interactive UI explicitly.

## Where things are stored

| Path | Contents |
| --- | --- |
| `~/.config/simbuddy/links.json` | Saved deep links |
| `~/.config/simbuddy/apps.json` | Saved app bundle identifiers |

Both are plain JSON, safe to edit, commit, or sync.

## Requirements

- macOS 13 or newer
- Xcode with at least one iOS Simulator runtime
- Swift 6.0 or newer to build from source
- A terminal at least 78×18

## Development

```bash
swift build
swift test
swift run simbuddy doctor
```

Simulator operations, terminal rendering, and command parsing live in separate
modules so each is testable on its own:

| Module | Responsibility |
| --- | --- |
| `SimctlBuddyCore` | `simctl` calls, device resolution, saved-link and saved-app stores |
| `SimctlBuddyTUI` | Terminal handling, interface state, rendering |
| `SimctlBuddyCLI` | Command and argument parsing |

### Safety

SimctlBuddy deliberately ships no simulator deletion or erase command. Actions
that change app data or privacy settings always require an explicit bundle
identifier.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
