# Contributing to SimctlBuddy

Thanks for helping make iOS Simulator workflows friendlier.

## Development setup

1. Install Xcode and an iOS Simulator runtime.
2. Clone the repository.
3. Run `swift test`.
4. Run `swift run simbuddy --help` to exercise the CLI locally.

## Pull requests

- Keep commands focused on common Simulator development workflows.
- Prefer public `xcrun simctl` behavior over private frameworks.
- Include tests for parsing, selection, validation, and persistence logic.
- Update the README when adding or changing a user-facing command.
- Keep destructive behavior explicit and difficult to trigger accidentally.

Please open an issue before investing in a large feature so its scope and CLI
shape can be discussed first.
