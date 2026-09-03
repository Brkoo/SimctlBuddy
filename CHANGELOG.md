# Changelog

## 0.3.0 - 2026-09-03

- Complete a path with `Tab` in every field that holds one: installing an
  `.app`, choosing a push payload, setting a capture folder, and importing or
  exporting deep links. Each field offers only entries it can accept, and an
  ambiguous match fills in as far as the names agree and lists the rest
- Save `.app` paths under names with `paths add`, install them with
  `install --saved <name>`, and pick them from a list in the interactive UI.
  Every successful install is remembered, so recent build paths are offered even
  if nothing was named
- Configure where captures go with `config set screenshot-directory` and
  `config set recording-directory`, or override per run with `--directory`
- Record the simulator screen: `simbuddy record` until `Ctrl+C`, or
  `--duration`. In the interactive UI, `R` starts and stops a recording, the
  header shows a red `● REC` chip with elapsed time, and quitting stops a running
  recording instead of orphaning it
- Terminate from a list of the apps actually running, read from the simulator's
  own launchd, with everything installed listed after them. `apps running` prints
  the same list for scripts
- Share deep links between machines with `links export` and `links import`.
  Existing names are kept unless `--force`, `--replace-all` replaces the whole
  set, and `--dry-run` shows what would change
- Drive physical iPhones and iPads, not just simulators. Devices come from
  `xcrun devicectl` and appear in the same list, marked as devices; deep links,
  install, launch, terminate, installed and running apps, screenshots, clipboard,
  location, appearance, and the status bar all work on hardware. Physical devices
  are opt-in: a command with no `--device` still only considers simulators
- Refuse what a device cannot do with the reason instead of the underlying tool's
  error — a phone has no boot state, no simulated push, and no privacy database —
  and leave those actions out of the interactive UI when a device is highlighted
- Refuse the wrong kind of build before installing it. A simulator build and a
  device build are both arm64 on Apple silicon, so the check reads
  `DTPlatformName` and the provisioning profile, and names the folder the right
  build is usually in
- Say why a device cannot be used rather than treating it as a typo: a paired but
  disconnected phone now reports that it is not connected, and a shut-down
  simulator that it needs booting
- Write a deep link once for every app it applies to. Saved apps gain a URL
  scheme, and a link written with `$scheme` resolves it from the app it is opened
  on, so one definition covers every market instead of one entry per scheme
- Give deep links parameters: `$name` asks for a value, `$name=value` supplies a
  default, `$0` and `$1` do the same by position, `${name=a&b}` brackets a
  default containing delimiters, and `$$` is a literal dollar. The interactive UI
  pre-fills each field with the value used last time; the command line takes
  `--set name=value` and errors rather than hanging when one is missing
- Restrict a deep link to the apps it belongs to with `links add --app`. Links
  resolve their app without asking when only one applies, or when only one of
  your saved apps is installed on the device, and ask when the choice is real
- Remember which app each link was last opened on, and reuse it when it still
  applies
- Add `SIMBUDDY_CONFIG_DIR` to point saved links, apps, paths, and settings at a
  different directory — a project's own set, or a throwaway one in CI
- Lay the interface out in terminal columns rather than characters. Nearly every
  glyph it draws is East Asian Ambiguous — the frame, `●`, `▶`, `↗`, `…` — which
  a terminal may draw one or two columns wide. Counting characters made every row
  wider than the window on a terminal that draws them wide, so rows wrapped, the
  frame pushed itself down, and the screen scrolled, leaving pieces of earlier
  frames behind: duplicated sections and several rows looking selected at once.
  The width of an ambiguous glyph is now measured from the terminal at startup
  (override with `SIMBUDDY_AMBIGUOUS_WIDTH`), the frame falls back to ASCII when
  they are double width, and auto-wrap is turned off so an over-long row is
  clipped instead of scrolling the screen
- Keep dialogs inside the window. A dialog is now clamped to the visible rows
  and columns instead of being centred on a size it does not fit, a short window
  lists fewer completion matches rather than growing, and resizing repaints from
  a clean slate — together these stop a shrinking window from leaving rows of the
  previous frame on screen, which looked like a second input field
- Add ROADMAP.md, covering physical device support through `xcrun devicectl`
  and the smaller items planned after it

- Pick a bundle identifier from the apps installed on the selected simulator
  instead of typing it, with type-to-search and `Tab` to enter one by hand
- Save app bundle identifiers under friendly names and launch them with Enter
- Add `bundles list`, `bundles add`, and `bundles remove` for saved apps
- Validate bundle identifiers as reverse-DNS before saving them

- Reach every feature from the interactive UI: send push notifications, grant,
  revoke, and reset privacy permissions, list installed apps, read the simulator
  clipboard, clear a location override, and run diagnostics
- Delete a saved deep link with `d`, completing add, edit, and delete
- Ask for confirmation before deleting a saved deep link
- Share one diagnostics implementation between `doctor` and the interactive UI

- Restore the terminal on `Ctrl+C` and on `SIGTERM`, `SIGHUP`, and `SIGQUIT`
  instead of leaving it in raw mode with the alternate screen still active
- Run every simctl command on a background queue with an animated spinner, so
  booting or installing no longer freezes the interface
- Add `/` to filter the focused panel: simulators by name or runtime, actions and
  saved deep links by title or URL
- Decode one key per read so fast typing and pastes no longer swallow shortcuts
- Drop hints from the footer instead of overflowing on narrow terminals

- Redesign the interactive UI so a tall terminal shows a dense deck instead of
  three near-empty columns
- Group actions into labelled sections (Links, Device, Apps, Capture,
  Appearance, System) with rule-style headers
- Split the left column into a device list and a persistent details card
- Add color throughout: boot state, keycaps, saved links, and success,
  warning, and error activity entries
- Wrap long activity entries so deep links stay readable instead of clipping
- Add a status bar showing the selected device and a booted/total tally
- Add Lazygit-style screen modes: `+` grows and `-` shrinks the focused panel
  through normal, half, and full layouts
- Show the active screen mode in the status bar
- Show help full width instead of squeezed into the output panel
- Keep more activity history now that the panel can show it
- Add empty-state hints when no simulators are available

## 0.2.2 - 2026-08-22

- Add an explicit `e` shortcut for editing the highlighted saved deep link
- Prefill the edit dialog with the current URL
- Add `Ctrl+U` to clear text fields quickly

## 0.2.1 - 2026-08-22

- Move text entry from the footer into centered terminal dialogs
- Add and update saved deep links directly from the interactive UI
- Show saved-link URLs in the details panel before opening them

## 0.2.0 - 2026-08-22

- Add a full-screen, three-panel terminal UI inspired by Lazygit
- Make `simbuddy` launch the interactive UI by default
- Add keyboard navigation, quick actions, prompts, inline help, and live output
- Keep every existing subcommand available for scripts and automation

## 0.1.0 - 2026-08-22

- Initial public release
- Friendly simulator discovery and device resolution
- Boot, shutdown, install, launch, terminate, and app listing commands
- Deep-link opening and reusable aliases
- Screenshots, clipboard, push notifications, location, and appearance
- Privacy controls and clean status-bar overrides
- Local environment diagnostics and JSON device output
