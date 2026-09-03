# Roadmap

What is planned, what it costs, and what will not happen. Nothing here is a
commitment to a date. Issues and pull requests against any item are welcome —
see [CONTRIBUTING.md](CONTRIBUTING.md).

## Contents

- [Delivered since this file was written](#delivered-since-this-file-was-written)
- [Physical device support](#physical-device-support)
- [Firebase App Distribution](#firebase-app-distribution)
- [Android support](#android-support)
- [Smaller items](#smaller-items)
- [Not planned](#not-planned)

## Delivered since this file was written

**Firebase App Distribution is now built** — see
[CHANGELOG.md](CHANGELOG.md) and the [App Distribution section of the
README](README.md#firebase-app-distribution). What remains of the section below
is the part still outstanding.

**Physical device support is now built** — see [CHANGELOG.md](CHANGELOG.md) and
the Physical devices section of the [README](README.md#physical-devices). What
remains of the section below is the part that is still outstanding: screen
recording on hardware, and platform-aware saved build paths.

Feedback from the team turned into shipped features rather than roadmap entries:
`Tab` completion in path fields, saved `.app` paths with recent installs,
configurable screenshot and recording folders, screen recording, terminating
from a list of running apps, and deep-link import and export. See
[CHANGELOG.md](CHANGELOG.md).

## Physical device support

SimctlBuddy shells out to `xcrun simctl`, which only ever talks to simulators.
Apple's `xcrun devicectl` is the equivalent for connected iPhones, iPads, and
Apple Watches, and it covers most of what SimctlBuddy already does. The goal is
one device list holding both kinds, with the Actions panel showing only what the
selected device actually supports.

### What maps across

| Action | `simctl` | `devicectl` |
| --- | --- | --- |
| List devices | `list devices --json` | `list devices --json-output <file>` |
| Open a deep link | `openurl` | `device process openURL --device X <url>` |
| Launch an app | `launch` | `device process launch --device X <bundle-id>` |
| Terminate an app | `terminate <bundle-id>` | `device process terminate --device X --pid <pid>` |
| List installed apps | `listapps` | `device info apps --device X` |
| Install an app bundle | `install` | `device install app --device X <path>` |
| Screenshot | `io screenshot` | `device capture screenshot --device X --destination <path>` |
| Screen recording | `io recordVideo` | `device capture screen-record --device X` |
| Copy to the clipboard | `pbcopy` | `device pasteboard copy --device X` |
| Read the clipboard | `pbpaste` | `device pasteboard paste --device X` |
| Set a location | `location set` | `device simulate location coordinate` |
| Clear a location | `location clear` | `device simulate location clear` |
| Override the status bar | `status_bar override` | `device simulate statusBar override` |
| Clear the status bar | `status_bar clear` | `device simulate statusBar clear` |
| Set the appearance | `ui appearance` | `device settings appearance` |

`devicectl` also offers a few things simulators cannot do at all, worth adding
as device-only actions: biometric success and failure events
(`device simulate biometrics`), display orientation (`device orientation`),
running processes (`device info processes`), and file transfer both ways
(`device copy`).

### What does not map

| Action | Why not |
| --- | --- |
| Boot and shut down | A physical device has no such state. `device reboot` exists, but it is a reboot, not a boot. |
| Send a push notification | `simctl push` fakes local delivery. Real devices need a real APNs round trip. `devicectl device notification post` sends Darwin notifications, which are a different mechanism entirely. |
| Grant, revoke, and reset privacy permissions | No `devicectl` equivalent. |
| Erase | `device settings reset` wipes the whole device, which is not the same thing and is far too destructive to expose. See [Safety](README.md#safety). |

That leaves roughly two thirds of the current feature set reachable on hardware,
plus the device-only additions. Losing push and privacy is the real cut.

### Work required

1. **A backend protocol.** `SimctlClient` is hardwired to `xcrun simctl` and
   returns stdout as a `String`. It needs to become a `DeviceBackend` protocol
   with `SimctlBackend` and `DevicectlBackend` conformances.
2. **JSON through a file.** `devicectl` documents `--json-output <path>` as the
   only supported interface for programs to read its results, so the new backend
   writes a temporary file, reads it, and parses a schema unrelated to
   `simctl`'s.
3. **Capabilities on the device model.** `SimulatorDevice` gains a backend and a
   supported-action set, so the Actions panel can dim push, privacy, boot, and
   shut down on a physical row instead of offering an action that fails when it
   runs.
4. **Terminate by process, not bundle identifier.** `devicectl` terminates a
   pid, so a `device info processes` lookup has to come first.
5. **A different state model.** `simctl` reports `Booted` or `Shutdown`.
   `devicectl` reports `connected`, `unavailable`, or `shutdown`, where
   `shutdown` means paired but not currently reachable. The existing
   `requireBooted` gate means something different per backend.

### Constraints worth documenting rather than solving

- The device must be paired and trusted, unlocked, and have Developer Mode on.
- Installing needs a signed build whose provisioning profile includes that
  device's UDID. There is no equivalent of dropping an unsigned `.app` onto a
  simulator.
- Wirelessly connected devices are slow and drop out, so every call needs a
  sensible `--timeout`.
- `pasteboard`, `capture`, `simulate location`, and `settings appearance` are
  recent `devicectl` additions. Older Xcode releases ship a `devicectl` without
  them, so `doctor` should report the `devicectl` version and the backend should
  gate on it.

## Firebase App Distribution

Fetching and installing builds from App Distribution is built. What follows is
what was learned doing it, and what is left.

### What is not possible, and will not become possible

- **Simulators.** App Distribution serves `.ipa` files for iOS — signed device
  binaries. It does not accept a zipped `.app`, and a simulator cannot run an
  IPA. This is a limit of the product, not of SimctlBuddy.
- **Installing an ad hoc build on an unregistered device.** The device UDID has
  to be inside the provisioning profile at build time. Firebase does not
  re-sign, so the only fix is a rebuild. SimctlBuddy detects this before
  installing and says so; it cannot work around it.
- **Zero configuration.** There is an account and an authorization boundary in
  the middle, so this can never be as configuration-free as `simctl`. The most
  that can be done — and is done — is to use a credential the machine already
  has rather than asking for a new one.
- **Being a tester is not enough.** Reading the API needs a project IAM role.
  Only a project admin can grant it.

### Still outstanding

- **Uploading.** Only reading and installing are built. `appdistribution:distribute`
  in the Firebase CLI already covers uploading well, and CI is the right place
  for it, so this is low priority.
- **Browsing projects in the interactive UI.** The command line can list a
  project's apps with `firebase apps --project`, but the interactive UI only
  offers saved apps. Browsing would mean two more API calls before anything
  useful appears on screen.
- **Tester and group management.** The API supports it. It is a different job
  from getting a build onto the phone in front of you, and belongs to whoever
  administers the project.
- **Android builds.** The API returns them, and they are refused with an
  explanation. Installing them needs `adb`, so this follows
  [Android support](#android-support) rather than standing alone — an APK needs
  no signing check at all, which makes it the easier half of that work.
- **A device-aware release list.** Every build could be marked installable or
  not against the selected device before it is picked, rather than at install
  time. That means downloading each build to read its profile, so it needs the
  cache to be warm to be worth doing.

## Android support

Planned, and a change of mind: this file previously listed Android as out of
scope. What follows is what it would take.

Two asks are easily confused here, and only the first is planned:

1. **Driving Android devices and emulators**, with SimctlBuddy still running on
   macOS. Moderate work, described below.
2. **Running SimctlBuddy on Linux or Windows.** A separate and much larger job,
   and [not planned](#not-planned).

`adb` and `emulator` ship with the Android SDK, so this stays within the rule
the rest of the tool follows: shell out to the platform's own public tools.

The port is the expensive half, and is what makes the two asks worth separating.
Signing a service account assertion uses Security.framework, reading a
provisioning profile shells out to `/usr/bin/security`, the terminal is driven
through Darwin's `termios`, and `URLSession` needs a different import on Linux.
None of that is insurmountable — RSA signing exists in swift-crypto's
`_CryptoExtras`, and the iOS-only paths would simply be absent — but it is a
rewrite of every seam the tool touches the system through, in exchange for
running somewhere the iOS half cannot work at all.

### What maps across

| Action | `simctl` | `adb` |
| --- | --- | --- |
| List devices | `list devices --json` | `devices -l` |
| Open a deep link | `openurl` | `shell am start -a android.intent.action.VIEW -d <url>` |
| Launch an app | `launch` | `shell monkey -p <pkg> -c android.intent.category.LAUNCHER 1` |
| Terminate an app | `terminate` | `shell am force-stop <pkg>` |
| List installed apps | `listapps` | `shell pm list packages -3` |
| Install a build | `install` | `install -r <apk>` |
| Screenshot | `io screenshot` | `exec-out screencap -p` |
| Screen recording | `io recordVideo` | `shell screenrecord`, then `pull` |
| Set the appearance | `ui appearance` | `shell cmd uimode night yes\|no` |
| Override the status bar | `status_bar override` | SystemUI demo mode broadcasts |
| Grant and revoke permissions | `privacy` | `shell pm grant` and `pm revoke` |
| Boot and shut down | `boot` / `shutdown` | `emulator -avd <name>` / `adb emu kill` |

### What Android does better than iOS hardware

Worth stating plainly, because it inverts the compromises the physical-device
work had to make:

- **No signing wall.** Any signed APK installs on any device. There is no
  provisioning profile, no UDID allowlist, and no rebuilding a build to add a
  device to it. The profile pre-flight check that App Distribution needs on iOS
  is simply unnecessary, which makes Android the easier target for that feature
  rather than the harder one.
- **Permissions work on real devices.** `pm grant` and `pm revoke` do what
  `simctl privacy` does, on hardware, which `devicectl` cannot.
- **Emulators have a real boot state**, so they behave like simulators rather
  than like phones.

### What does not map

| Action | Why not |
| --- | --- |
| Clipboard | No dependable public `adb` interface. Would be left out rather than half-worked. |
| Send a push notification | FCM needs a real server credential. `simctl push` fakes local delivery; there is no equivalent. |
| Set a location | `adb emu geo fix` is emulator-only. Real devices need a mock-location app installed. |
| Install an `.aab` | A bundle is not installable. It needs `bundletool` and a device spec, so App Distribution releases of that type should be refused with the reason. |

### Work required

1. **The backend protocol, finally.** `DeviceService` switches on `DeviceKind`
   in roughly twenty methods, which was tolerable for two kinds and will not be
   for four. This is the `DeviceBackend` protocol the physical-device section
   above describes and which was never built. Android is the forcing function.
2. **A build type that is not an app bundle.** `AppBundle` is hardwired to
   `DTPlatformName` and `embedded.mobileprovision`. It has to span `.app`,
   `.ipa`, and `.apk`, with the signing checks applying only where they mean
   something.
3. **Locating the SDK.** `adb` is not on `PATH` by default. `ANDROID_HOME`,
   `ANDROID_SDK_ROOT`, and `~/Library/Android/sdk/platform-tools` all have to be
   tried, and `doctor` should report which was used.
4. **More device kinds.** An emulator and a physical Android device differ over
   boot state and location the way simulators and iPhones do, so they are
   separate kinds rather than one.
5. **App Distribution by binary type.** The client already reports `IPA`, `APK`,
   and `AAB`. Once an Android backend exists, installing an APK release is
   nearly free; the type just has to pick the backend.

### Suggested order

The refactor first, alone, with no behaviour change and the existing tests still
green. Then listing and installing, then the Firebase path, then the long tail.
Doing it the other way around means writing the `switch` a third time.

## Smaller items

- A `--json` flag on the remaining read-only subcommands, so everything can be
  piped into `jq` without parsing table output. `devices` and `paths list`
  already have one.
- Saved push payloads under friendly names, alongside saved deep links, saved
  app bundle identifiers, and saved build paths.
- Shell completion for saved link, app, and path names, not only for
  subcommands. Path *fields* already complete on `Tab` inside the interactive
  UI; this is about the command line.
- Import and export for saved apps, build paths, and Firebase app IDs, matching `links export` and
  `links import`. Build paths are machine-specific, so an export would have to
  say so rather than pretend to be portable.
- A recording indicator that survives a crash. Quitting stops a recording, but a
  `SIGKILL` still orphans simctl; a pid file would let the next run offer to
  clean up.

## Not planned

- **Deleting or erasing simulators.** A deliberate omission, not an oversight.
  See [Safety](README.md#safety).
- **Anything using private frameworks or accessibility permissions.**
  SimctlBuddy shells out to the platform's own public tools — `simctl`,
  `devicectl`, and `adb` — and intends to keep doing so.
- **Running SimctlBuddy anywhere but macOS.** Android support does not require
  it — Android development happens on macOS perfectly well, and the two are
  separate decisions. See [Android support](#android-support) for why the port
  is the expensive half and the one not being taken.
