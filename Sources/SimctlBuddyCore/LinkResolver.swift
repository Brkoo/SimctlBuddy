import Foundation

/// Works out which app a deep link should be opened on, so the interactive UI
/// and the command line agree about when a choice is needed and when one app is
/// the obvious answer.
public enum LinkResolver {
  /// The saved apps that could open this link.
  ///
  /// A link restricted to bundle identifiers only offers those. A link written
  /// with `$scheme` only offers apps that have a scheme, since the others could
  /// not produce a URL. Apps installed on the device come first.
  public static func candidates(
    for link: SavedLink,
    apps: [SavedApp],
    installed: [String] = []
  ) -> [SavedApp] {
    let template = link.template
    let installedSet = Set(installed.map { $0.lowercased() })
    return apps
      .filter { link.appliesTo(bundleIdentifier: $0.bundleIdentifier) }
      .filter { !template.requiresScheme || $0.scheme != nil }
      .sorted { first, second in
        let firstInstalled = installedSet.contains(first.bundleIdentifier.lowercased())
        let secondInstalled = installedSet.contains(second.bundleIdentifier.lowercased())
        if firstInstalled != secondInstalled { return firstInstalled }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
      }
  }

  /// The app to use without asking, or nil when the choice is genuinely open.
  ///
  /// A remembered app wins, then a single candidate. Anything else is a question
  /// for the person running the link.
  public static func automaticChoice(
    from candidates: [SavedApp],
    remembered: String?
  ) -> SavedApp? {
    if let remembered,
      let match = candidates.first(where: {
        $0.bundleIdentifier.caseInsensitiveCompare(remembered) == .orderedSame
      })
    {
      return match
    }
    return candidates.count == 1 ? candidates[0] : nil
  }

  /// Finds a saved app by name or bundle identifier, the way `--app` is written.
  public static func app(matching selector: String, in apps: [SavedApp]) throws -> SavedApp {
    if let exact = apps.first(where: {
      $0.bundleIdentifier.caseInsensitiveCompare(selector) == .orderedSame
        || $0.name.caseInsensitiveCompare(selector) == .orderedSame
    }) {
      return exact
    }
    let partial = apps.filter {
      $0.name.localizedCaseInsensitiveContains(selector)
        || $0.bundleIdentifier.localizedCaseInsensitiveContains(selector)
    }
    if partial.count == 1 { return partial[0] }
    if partial.count > 1 {
      throw SimctlBuddyError.ambiguousDevice(
        selector, matches: partial.map { "\($0.name) [\($0.bundleIdentifier)]" })
    }
    throw SimctlBuddyError.appNotFound(selector)
  }

  /// Parses `--set name=value` pairs.
  public static func parseAssignments(_ assignments: [String]) throws -> [String: String] {
    var result = [String: String]()
    for assignment in assignments {
      guard let equals = assignment.firstIndex(of: "=") else {
        throw SimctlBuddyError.invalidAssignment(assignment)
      }
      let name = String(assignment[assignment.startIndex..<equals])
        .trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty else { throw SimctlBuddyError.invalidAssignment(assignment) }
      result[name] = String(assignment[assignment.index(after: equals)...])
    }
    return result
  }
}
