<div align="center">

# SimctlBuddy

**A Lazygit-style terminal UI for the iOS Simulator — and your iPhone.**

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
- [Firebase App Distribution](#firebase-app-distribution)
- [Scripting](#scripting)
- [Where things are stored](#where-things-are-stored)
- [Requirements](#requirements)
- [Development](#development)
- [Roadmap](ROADMAP.md)

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
| `e` | Edit the highlighted saved link, app, or build |
| `d` | Delete the highlighted saved link, app, or build |
| `b` / `x` | Boot or shut down the simulator |
| `i` | Install an `.app` bundle |
| `f` | Install a build from Firebase App Distribution |
| `L` / `t` | Launch or terminate an app |
| `p` | Send a push notification |
| `s` | Take a screenshot |
| `R` | Start or stop a screen recording |
| `c` / `v` | Copy text to, or read text from, the simulator clipboard |
| `g` | Set a location |
| `r` | Refresh devices |

### Picking apps instead of typing identifiers

Launch, push, and the privacy actions open a searchable list of the apps
installed on the selected simulator, with your saved apps at the top:

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

**Terminate** lists the apps that are *running* first, because those are the only
ones worth terminating, with everything installed after them:

```text
┌ Terminate app ────────────────────────────────────┐
│ /▌                                                │
│                                                   │
│❯ com.example.Checkout  running                    │
│  com.apple.mobilecal   running                    │
│  com.apple.MobileSMS   installed                  │
│                                                   │
│ ↑/↓ move · Enter choose · Tab type it · Esc cancel│
└───────────────────────────────────────────────────┘
```

**Install** lists your saved builds first, then the paths you installed most
recently, so a build path is something you pick rather than retype.

### Completing paths with Tab

Every field that holds a path completes on `Tab`: installing an `.app`, choosing a
push payload, setting the screenshot or recording folder, and importing or
exporting deep links. Each field offers only what it can accept — `.app` bundles
for an install, folders for a capture folder.

```text
┌ Install app ──────────────────────────────────────┐
│                                                   │
│ Path to .app                                      │
│ › ~/Build/Products/Debug-iphonesimulator/Che▌     │
│ 2 matches                                         │
│ Checkout.app   Checkout-Staging.app               │
│                                                   │
│ Enter confirm · Tab complete · Ctrl+U clear · Esc │
└───────────────────────────────────────────────────┘
```

One match fills the field in. Several fill in as far as they agree and list the
rest underneath, so pressing `Tab` never deletes what you typed.

### Saving links, apps, and builds

Deep links, bundle identifiers, and build paths you use repeatedly get names and
their own sections in the actions panel.

- Press `a` to save a deep link, then `Enter` on it to open it.
- Choose **Save app bundle ID** to name an app, then `Enter` on it to launch it.
- Choose **Save .app path** to name a build, then `Enter` on it to install it.
- On any of them, `e` edits and `d` deletes. Deletions ask first.

A saved build whose path is not on disk right now is still kept — build
directories come and go — and the details card says so rather than failing only
once you try to install it.

### Recording

`R` starts a recording and `R` stops it. While one is running the header shows a
red `● REC` chip with the elapsed time, and the details card repeats the
filename, so a forgotten recording is hard to miss.

```text
 ● iPhone 16  iOS 26.0  Booted   ● REC 1:24      normal · 1 booted · 9 total
```

Recordings are finalized on stop, and quitting the interface stops a running
recording rather than orphaning it.

### Deep links that ask for what they need

A link written with `$scheme` or `$name` collects the missing pieces before it
opens. Running **staging-slot** on a machine with two markets saved asks which
app, then asks for the value:

```text
┌ Open on which app? ───────────────────────────────┐
│ /▌                                                │
│                                                   │
│❯ SparAT  sparatappqa://                           │
│  SparSI  sparsiappqa://                           │
│                                                   │
│ ↑/↓ move · Enter choose · Tab type it · Esc cancel│
└───────────────────────────────────────────────────┘

┌ staging-slot · $slot ─────────────────────────────┐
│                                                   │
│ Value for $slot                                   │
│ › staging5▌                                       │
│ Example: staging5                                 │
│                                                   │
│ Enter confirm  ·  Ctrl+U clear  ·  Esc cancel     │
└───────────────────────────────────────────────────┘
```

The field starts from the value you used last time, falling back to the
template's default. The app you chose is remembered too, so the second run of
the same link usually skips straight to the parameter. The details card lists
what a link needs before you run it.

Saving an app now also asks for its URL scheme — leave it empty for an app that
has none, and `$scheme` links simply will not offer it.

### Sharing deep links

**Export deep links** writes your saved links to a file, and **Import deep
links** merges a file back in. The exported file has the same shape as
`links.json`, so it can live in a repository and be imported on another machine
as-is. An import never overwrites a link you already have: colliding names are
reported as skipped, and `e` edits one by hand.

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

### If the layout looks wrong

Almost every glyph the interface draws — the frame, `●`, `▶`, `↗`, `…` — is
"East Asian Ambiguous", which means one column wide in some terminals and two in
others. SimctlBuddy measures which at startup by drawing one and asking the
terminal where the cursor ended up, then lays out in real columns and switches to
an ASCII frame when the glyphs are double width. It also turns off auto-wrap, so
a row that still ends up too long is clipped rather than wrapping and scrolling
the screen.

If your terminal does not answer the measurement, or answers wrongly, set it by
hand:

```bash
SIMBUDDY_AMBIGUOUS_WIDTH=2 simbuddy
```

`1` is the common case; `2` suits a terminal set to treat ambiguous-width
characters as double width. When the value is 2 the activity panel says so at
startup, which is a quick way to confirm what was measured.

### Nothing blocks

Booting a simulator or installing an app runs in the background with a spinner in
the activity panel. The interface stays responsive and you can keep navigating
while it finishes.

## Firebase App Distribution

Install a build straight from App Distribution onto a connected device, without
opening a browser, downloading an `.ipa` by hand, or unpacking anything.

Press `f`, pick an app, pick a build. The list shows the version, how long ago it
was uploaded, and the first line of its release notes, and it is searchable like
every other picker.

### Simulators cannot be reached, and that is not a bug

App Distribution serves `.ipa` files, which are signed iOS binaries. A simulator
cannot run one. The App Distribution rows only appear when a physical device is
selected, so the action is never offered where it could only fail.

Simulator builds still install the ordinary way, with `simbuddy install`.

### Signing is checked before the install, not after

An ad hoc build only installs on devices whose UDID was in its provisioning
profile **when it was built**. Firebase does not re-sign anything, so a device
registered after the build was made cannot run it — the fix is a rebuild, and no
tool can work around it.

SimctlBuddy reads the profile inside the downloaded build and compares it against
the device's UDID before installing, so you get this:

```
✗ 1.2.0 (88) is not signed for Karlo's iPhone.
  Its profile (MyApp AdHoc) lists 12 devices, and this one is not among them.
  An ad hoc build only installs on devices registered before it was built, so
  this needs a rebuild with the device added. Pass --force to try anyway.
```

rather than an install that fails on the phone with a signing error. Enterprise
builds carry no device list and install anywhere, and are reported as such.

### Signing in

SimctlBuddy does not have its own login. It uses a Google credential the machine
already has, trying each in turn:

| Source | How to get one |
| --- | --- |
| `SIMBUDDY_FIREBASE_TOKEN` | An access token, for CI |
| A service account key | `simbuddy config set firebase-service-account <path>`, or `GOOGLE_APPLICATION_CREDENTIALS` |
| gcloud | `gcloud auth login` |
| Firebase CLI | `firebase login` |

`simbuddy firebase status` says which one it found and whether it works. In the
interactive UI, the **Firebase setup** action does the same and prints the steps
to follow when nothing is set up yet.

You need to be a **project member** with the Firebase App Distribution Viewer
role, or higher. Being a tester is not enough — testers can install from the web
clip but cannot read the API, and that comes back as a permission error only a
project admin can fix.

Nothing here costs money: App Distribution is free on both the Spark and Blaze
plans.

### Setting it up

If your team already uploads builds to App Distribution, the project side is
done — registering the app, clicking **Get started** on the App Distribution
page, and enabling the API are all prerequisites for uploading. All that is left
is a credential and the app ID:

```bash
simbuddy firebase save staging 1:1234567890:ios:abc123
simbuddy firebase releases staging
simbuddy firebase install staging --launch
```

### Finding an app ID

An app ID looks like `1:1234567890:ios:abc123def456`. The middle field is the
project number, which is why saving the ID is enough — SimctlBuddy never has to
ask which project an app belongs to.

You do not have to go looking for it. This walks every project you can see:

```bash
simbuddy firebase apps --all
```

In the interactive UI, **Save Firebase app ID** does the same thing and presents
the result as a list to pick from. `Tab` still lets you type an ID by hand.

If you would rather read it off the console: **Project settings › General › Your
apps**, select the iOS app, and it is the field labelled **App ID**. It is also
the `GOOGLE_APP_ID` value inside `GoogleService-Info.plist`, if you have one in
the repo.

Access is granted per project, so `--all` reports any project it could not read
at the end rather than stopping. A project listed there is one where you lack the
App Distribution Viewer role — being a tester on it is not enough.

### Commands

```bash
simbuddy firebase status                    # which credential will be used
simbuddy firebase projects                  # projects you can see
simbuddy firebase apps                      # saved apps
simbuddy firebase apps --all                # every app in every project
simbuddy firebase apps --project my-project # iOS apps in one project
simbuddy firebase save staging <appId>      # remember an app ID
simbuddy firebase forget staging
simbuddy firebase releases staging          # builds, newest first
simbuddy firebase releases staging --filter 'displayVersion="1.2.0"'
simbuddy firebase install staging           # newest build
simbuddy firebase install staging <releaseId>
simbuddy firebase install staging --force   # install despite a profile mismatch
simbuddy firebase clean                     # delete downloaded builds
```

Downloads are cached under `~/Library/Caches/simbuddy/firebase/`, so installing
the same build twice only fetches it once.

## Scripting

Every subcommand defaults to the only booted simulator. Pass `--device` (`-d`)
with a name, partial name, or UDID to target a specific one. Partial names are
accepted when they identify exactly one device; ambiguous matches list the
candidates rather than guessing.

### Devices

```bash
simbuddy devices              # simulators and connected devices
simbuddy devices --booted
simbuddy devices --devices-only
simbuddy devices --json
simbuddy boot                 # a sensible default iPhone
simbuddy boot "17 Pro"        # or a partial name
simbuddy shutdown
```

### Physical devices

Most commands work on a real iPhone or iPad through `xcrun devicectl`. Name one
with `--device`, or pass `--devices-only`:

```bash
simbuddy devices --devices-only
simbuddy apps --device "Horvat iOS"
simbuddy apps running --device "Horvat iOS"
simbuddy open 'myapp://profile/42' --device "Horvat iOS"
simbuddy install ./Build/Products/Debug-iphoneos/MyApp.app --device "Horvat iOS"
simbuddy launch com.example.MyApp --device "Horvat iOS"
simbuddy terminate com.example.MyApp --device "Horvat iOS"
simbuddy screenshot --device "Horvat iOS"
```

**Physical devices are opt-in.** With no `--device`, only simulators are
considered, so plugging a phone in cannot make every command ambiguous or aim an
install at hardware by accident.

What works on each kind:

| Action | Simulator | Device |
| --- | --- | --- |
| List, open deep links | yes | yes |
| Install, launch, terminate | yes | yes |
| List installed and running apps | yes | yes |
| Screenshot | yes | yes |
| Clipboard, location, appearance, status bar | yes | yes |
| Boot, shut down | yes | no — a phone has no boot state |
| Push notification | yes | no — needs a real APNs delivery |
| Privacy permissions | yes | no — devicectl cannot change them |
| Screen recording | yes | not yet wired |

An action a device cannot do is refused with the reason, and is not listed for
that device in the interactive UI.

Installing on hardware needs what Xcode needs: the device paired and unlocked,
Developer Mode on, and a build signed with a provisioning profile that includes
it. Simulator and device builds are not interchangeable — SimctlBuddy reads
`DTPlatformName` from the bundle and refuses the wrong one with the fix rather
than letting the signing error surface:

```
$ simbuddy install ./Build/Products/Debug-iphonesimulator/MyApp.app --device "Horvat iOS"
Error: MyApp.app cannot be installed on a device. That is a simulator build.
The device build is usually the -iphoneos folder beside it, and has to be signed
for this device.
```

### Deep links

```bash
simbuddy open 'myapp://profile/42?source=terminal'
simbuddy open 'myapp://debug' --device 'iPhone 17 Pro'

simbuddy links add login 'myapp://login?mode=test'
simbuddy links run login
simbuddy links list
simbuddy links remove login

simbuddy links add profile '$scheme://profile/$0?ref=$1'
simbuddy links run profile --app SparAT --set 0=42 --set 1=terminal

simbuddy links export team-links.json
simbuddy links export | jq '.[].name'      # or straight to stdout
simbuddy links import team-links.json --dry-run
simbuddy links import team-links.json      # existing names are kept
simbuddy links import team-links.json --force
```

### Deep links that vary by app

A link can be written once and opened on any of your apps. Give each saved app
its URL scheme, then write `$scheme` instead of spelling one out:

```bash
simbuddy bundles add SparAT at.spar.mobile.spar-app.ent.qa --scheme sparatappqa
simbuddy bundles add SparSI si.spar.plus.ent.qa            --scheme sparsiappqa

simbuddy links add bills '$scheme://navigate/bills'
simbuddy links run bills --app SparAT     # sparatappqa://navigate/bills
simbuddy links run bills --app SparSI     # sparsiappqa://navigate/bills
```

`--app` takes a saved app's name or bundle identifier. You can leave it out when
the answer is obvious: a link restricted to one app, or only one of your apps
installed on the device. When several could apply, SimctlBuddy says so and lists
them rather than picking a market for you.

Restrict a link to the apps it belongs to:

```bash
simbuddy links add purchase '$scheme://navigate/purchasepopup' \
  --app at.spar.mobile.spar-app.ent.qa
```

#### Parameters

`$name` asks for a value when the link runs. `$name=value` gives it a default:

```bash
simbuddy links add staging-slot '$scheme://automation?staging-slot=$slot=staging5'

simbuddy links run staging-slot --app SparAT                    # ...=staging5
simbuddy links run staging-slot --app SparAT --set slot=staging7 # ...=staging7
```

| Syntax | Meaning |
| --- | --- |
| `$scheme` | Filled in from the app the link is opened on |
| `$name` | Asked for when the link runs |
| `$name=value` | Asked for, starting from `value` |
| `$0`, `$1` | The same, written by position |
| `${name=a&b}` | Brackets a default that contains `&`, `/`, `?`, or `#` |
| `$$` | A literal dollar sign |

In the interactive UI a parameter is a dialog, pre-filled with the value you used
last time, falling back to the default. On the command line, values come from
`--set` and defaults; a missing one is an error naming the parameter, so a script
never hangs waiting for input.

A finished URL is still a finished URL — existing saved links keep working
untouched, and only gain this behaviour if you rewrite them with `$`.

`import` keeps what you already have and reports colliding names as skipped.
`--force` overwrites those, `--replace-all` replaces the whole set, and
`--dry-run` prints what would change without writing anything.

### Apps

```bash
simbuddy install ./Build/MyApp.app
simbuddy launch com.example.MyApp
simbuddy launch com.example.MyApp --restart -- --uitesting --skip-onboarding
simbuddy terminate com.example.MyApp
simbuddy apps                 # installed apps, as JSON
simbuddy apps list --identifiers
simbuddy apps running         # bundle identifiers running right now

simbuddy bundles add checkout com.example.Checkout
simbuddy bundles list
simbuddy bundles remove checkout
```

Arguments after `--` in `launch` are forwarded to the app.

`apps running` reads the simulator's own launchd, so it pairs with `terminate` in
a script:

```bash
simbuddy apps running | grep '^com.example' | xargs -n1 simbuddy terminate
```

### Build paths

Name the builds you install repeatedly instead of pasting paths out of
DerivedData:

```bash
simbuddy paths add staging ~/Build/Products/Debug-iphonesimulator/MyApp.app
simbuddy paths list           # saved paths, then recently installed ones
simbuddy paths list --json
simbuddy install --saved staging
simbuddy install ./Build/MyApp.app --save-as nightly
simbuddy paths remove staging
simbuddy paths forget-recent
```

Every successful install is remembered, so `paths list` shows what you installed
recently even if you never named anything. A saved path is kept even when the
build is not on disk right now; `paths list` marks those with `!`.

### Screenshots, recordings, and status bar

```bash
simbuddy statusbar clean      # 9:41, full bars, full battery
simbuddy screenshot screenshots/login.png
simbuddy screenshot                        # simbuddy-<timestamp>.png
simbuddy screenshot --directory ~/Desktop
simbuddy statusbar clear

simbuddy record                            # until Ctrl+C
simbuddy record bug.mov
simbuddy record --duration 10 --codec hevc
```

With no path, captures are named `simbuddy-<timestamp>` and land in the folder
you configured, or in the working directory when you have not configured one:

```bash
simbuddy config list
simbuddy config set screenshot-directory ~/Desktop/simulator-shots
simbuddy config set recording-directory ~/Desktop/simulator-recordings
simbuddy config get screenshot-directory
simbuddy config unset screenshot-directory
```

Directories are created if they do not exist yet. `record` writes a QuickTime
movie and stops on `Ctrl+C`, finalizing the file before it exits — so a recording
is never left truncated, and `--duration` does the same thing on a timer.

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
| `~/.config/simbuddy/paths.json` | Saved `.app` paths, and recently installed ones |
| `~/.config/simbuddy/firebase.json` | Saved Firebase app IDs |
| `~/.config/simbuddy/settings.json` | Screenshot and recording folders, Firebase service account |
| `~/.config/simbuddy/link-values.json` | The last value used for each link parameter |
| `~/Library/Caches/simbuddy/firebase/` | Unpacked App Distribution builds |

All of them are plain JSON, safe to edit, commit, or sync.

Set `SIMBUDDY_CONFIG_DIR` to keep a separate set — a project's own links, or a
throwaway directory in CI:

```bash
SIMBUDDY_CONFIG_DIR=./.simbuddy simbuddy links list
```

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
What is planned next, including support for physical devices, is in
[ROADMAP.md](ROADMAP.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
