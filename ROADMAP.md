# Roadmap

What is planned, what it costs, and what will not happen. Nothing here is a
commitment to a date. Issues and pull requests against any item are welcome —
see [CONTRIBUTING.md](CONTRIBUTING.md).

## Contents

- [Delivered since this file was written](#delivered-since-this-file-was-written)
- [Physical device support](#physical-device-support)
- [Smaller items](#smaller-items)
- [Not planned](#not-planned)

## Delivered since this file was written

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

## Smaller items

- A `--json` flag on the remaining read-only subcommands, so everything can be
  piped into `jq` without parsing table output. `devices` and `paths list`
  already have one.
- Saved push payloads under friendly names, alongside saved deep links, saved
  app bundle identifiers, and saved build paths.
- Shell completion for saved link, app, and path names, not only for
  subcommands. Path *fields* already complete on `Tab` inside the interactive
  UI; this is about the command line.
- Import and export for saved apps and build paths, matching `links export` and
  `links import`. Build paths are machine-specific, so an export would have to
  say so rather than pretend to be portable.
- A recording indicator that survives a crash. Quitting stops a recording, but a
  `SIGKILL` still orphans simctl; a pid file would let the next run offer to
  clean up.

## Not planned

- **Deleting or erasing simulators.** A deliberate omission, not an oversight.
  See [Safety](README.md#safety).
- **Anything using private frameworks or accessibility permissions.**
  SimctlBuddy shells out to public Apple tools and intends to keep doing so.
- **Android or cross-platform device support.** Out of scope.
