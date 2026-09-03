import Foundation

/// Where saved links, apps, paths, settings, and remembered values live.
///
/// `SIMBUDDY_CONFIG_DIR` overrides the default, which keeps a project's own
/// links out of your personal ones and lets a CI job or a test run against a
/// throwaway directory.
public enum ConfigDirectory {
  public static let environmentKey = "SIMBUDDY_CONFIG_DIR"

  public static var url: URL {
    if let override = ProcessInfo.processInfo.environment[environmentKey],
      !override.trimmingCharacters(in: .whitespaces).isEmpty
    {
      return URL(fileURLWithPath: SettingsStore.absolutePath(override), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("simbuddy", isDirectory: true)
  }

  public static func file(_ name: String) -> URL {
    url.appendingPathComponent(name)
  }
}
