# Changelog

## Unreleased

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
