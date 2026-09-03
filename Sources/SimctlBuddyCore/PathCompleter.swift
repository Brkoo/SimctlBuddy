import Foundation

/// One entry in a directory, as much as path completion needs to know about it.
public struct PathEntry: Equatable, Sendable {
  public let name: String
  public let isDirectory: Bool

  public init(name: String, isDirectory: Bool) {
    self.name = name
    self.isDirectory = isDirectory
  }
}

/// What kind of path a field expects, so completion only offers entries that
/// could actually be accepted.
public enum PathFilter: Equatable, Sendable {
  case any
  case directories
  /// Directories, because you have to walk through them, with `.app` bundles
  /// treated as the destination rather than as somewhere to descend into.
  case appBundles
  case files(extensions: [String])
}

/// The outcome of one completion attempt.
public struct PathCompletion: Equatable, Sendable {
  /// What the field should contain now. Equal to the input when nothing matched
  /// or when several matches share no more characters than were already typed.
  public let value: String
  /// Every matching entry, for display when the completion is ambiguous.
  public let candidates: [String]
  /// True when `value` names exactly one entry.
  public let isUnique: Bool

  public init(value: String, candidates: [String], isUnique: Bool) {
    self.value = value
    self.candidates = candidates
    self.isUnique = isUnique
  }
}

/// Tab completion for path fields. The directory listing is injected so the
/// rules can be tested without touching the file system.
public struct PathCompleter: Sendable {
  private let list: @Sendable (String) -> [PathEntry]
  private let currentDirectory: @Sendable () -> String

  public init(
    list: (@Sendable (String) -> [PathEntry])? = nil,
    currentDirectory: (@Sendable () -> String)? = nil
  ) {
    self.list = list ?? Self.listFileSystem
    self.currentDirectory = currentDirectory ?? { FileManager.default.currentDirectoryPath }
  }

  public func complete(_ partial: String, filter: PathFilter = .any) -> PathCompletion {
    let (directoryText, prefix) = Self.split(partial)
    let searchPath = resolve(directoryText)
    let matches = list(searchPath)
      .filter { Self.matches($0, prefix: prefix, filter: filter) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    guard let first = matches.first else {
      return PathCompletion(value: partial, candidates: [], isUnique: false)
    }

    if matches.count == 1 {
      return PathCompletion(
        value: directoryText + first.name + Self.suffix(for: first, filter: filter),
        candidates: [first.name],
        isUnique: true
      )
    }

    // Several matches: fill in as far as they agree, and let the caller list the
    // rest. Anything shorter than what was typed would delete characters.
    let shared = Self.commonPrefix(of: matches.map(\.name))
    let names = matches.map { $0.name + Self.suffix(for: $0, filter: filter) }
    guard shared.count > prefix.count else {
      return PathCompletion(value: partial, candidates: names, isUnique: false)
    }
    return PathCompletion(value: directoryText + shared, candidates: names, isUnique: false)
  }

  /// Splits a partial path into the directory text to search, kept exactly as
  /// typed so a leading `~` survives, and the fragment being completed.
  static func split(_ partial: String) -> (directory: String, prefix: String) {
    guard let index = partial.lastIndex(of: "/") else { return ("", partial) }
    let boundary = partial.index(after: index)
    return (String(partial[..<boundary]), String(partial[boundary...]))
  }

  private func resolve(_ directoryText: String) -> String {
    guard !directoryText.isEmpty else { return currentDirectory() }
    let expanded = NSString(string: directoryText).expandingTildeInPath
    let absolute =
      expanded.hasPrefix("/")
      ? expanded
      : NSString(string: currentDirectory()).appendingPathComponent(expanded)
    return NSString(string: absolute).standardizingPath
  }

  private static func matches(_ entry: PathEntry, prefix: String, filter: PathFilter) -> Bool {
    // Dotfiles stay out of the way until they are asked for by name.
    if entry.name.hasPrefix("."), !prefix.hasPrefix(".") { return false }
    guard entry.name.lowercased().hasPrefix(prefix.lowercased()) else { return false }

    switch filter {
    case .any:
      return true
    case .directories, .appBundles:
      return entry.isDirectory
    case .files(let extensions):
      if entry.isDirectory { return true }
      return extensions.contains { entry.name.lowercased().hasSuffix(".\($0.lowercased())") }
    }
  }

  /// A trailing slash means "keep going", so it is wrong on a bundle that is
  /// itself the answer.
  private static func suffix(for entry: PathEntry, filter: PathFilter) -> String {
    guard entry.isDirectory else { return "" }
    if filter == .appBundles, entry.name.lowercased().hasSuffix(".app") { return "" }
    return "/"
  }

  /// Case-insensitive, but the characters come from a real entry so the field
  /// ends up with the spelling on disk.
  private static func commonPrefix(of names: [String]) -> String {
    guard var result = names.first else { return "" }
    for name in names.dropFirst() {
      result = result.commonPrefix(with: name, options: [.caseInsensitive])
    }
    return result
  }

  private static let listFileSystem: @Sendable (String) -> [PathEntry] = { path in
    let manager = FileManager.default
    guard let names = try? manager.contentsOfDirectory(atPath: path) else { return [] }
    return names.map { name in
      var isDirectory: ObjCBool = false
      let full = NSString(string: path).appendingPathComponent(name)
      _ = manager.fileExists(atPath: full, isDirectory: &isDirectory)
      return PathEntry(name: name, isDirectory: isDirectory.boolValue)
    }
  }
}
