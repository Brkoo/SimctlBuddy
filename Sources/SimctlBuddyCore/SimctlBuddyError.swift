import Foundation

public enum SimctlBuddyError: LocalizedError, Equatable {
  case commandFailed(command: String, exitCode: Int32, message: String)
  case invalidResponse(String)
  case noBootedDevice
  case deviceNotFound(String)
  case ambiguousDevice(String, matches: [String])
  case invalidURL(String)
  case invalidCoordinate(latitude: Double, longitude: Double)
  case invalidAppBundle(String)
  case linkNotFound(String)
  case duplicateLink(String)
  case appNotFound(String)
  case duplicateApp(String)
  case invalidBundleIdentifier(String)
  case setupProblem(String)
  case missingFile(String)
  case notADirectory(String)
  case cannotCreateDirectory(String, reason: String)
  case notAnAppBundlePath(String)
  case pathNotFound(String)
  case duplicatePath(String)
  case recordingAlreadyRunning(String)
  case noRecordingRunning
  case recordingFailed(String)
  case invalidImportFile(String)
  case missingLinkScheme
  case missingLinkParameter(String)
  case appHasNoScheme(String)
  case noSchemeForLink(String)
  case invalidScheme(String)
  case invalidAssignment(String)
  case appNotInstalled(String, device: String)
  case appNotRunning(String, device: String)
  case unsupportedAction(DeviceCapability, kind: DeviceKind)
  case devicectlUnavailable
  case wrongBuildForDevice(name: String, kind: DeviceKind, hint: String)
  case networkFailed(String)
  case noFirebaseCredential
  case invalidServiceAccount(String)
  case firebaseAccessDenied(String)
  case invalidFirebaseAppID(String)
  case duplicateFirebaseApp(String)
  case firebaseAppNotFound(String)
  case firebaseNeedsPhysicalDevice
  case releaseHasNoBinary(String)
  case invalidArchive(String)
  case deviceNotInProfile(release: String, device: String, profile: String, deviceCount: Int)

  public var errorDescription: String? {
    switch self {
    case .commandFailed(let command, let exitCode, let message):
      return "Command failed (\(exitCode)): \(command)\n\(message)"
    case .invalidResponse(let message):
      return "Could not understand simctl output: \(message)"
    case .noBootedDevice:
      return
        "Nothing is ready to act on. Boot a simulator with `simbuddy boot`, or pass --device."
    case .deviceNotFound(let selector):
      return
        "No available simulator matched “\(selector)”. Run `simbuddy devices` to see your options."
    case .ambiguousDevice(let selector, let matches):
      return
        "“\(selector)” matches multiple simulators: \(matches.joined(separator: ", ")). Use a full name or UDID."
    case .invalidURL(let value):
      return
        "“\(value)” is not a valid deep link. Include a scheme, for example myapp://profile/42."
    case .invalidCoordinate(let latitude, let longitude):
      return
        "Invalid coordinate \(latitude),\(longitude). Latitude must be -90...90 and longitude -180...180."
    case .invalidAppBundle(let path):
      return "No .app bundle exists at \(path)."
    case .linkNotFound(let name):
      return "No saved link named “\(name)”. Run `simbuddy links list` to see saved links."
    case .duplicateLink(let name):
      return "A saved link named “\(name)” already exists. Pass --force to replace it."
    case .appNotFound(let name):
      return "No saved app named “\(name)”. Run `simbuddy bundles list` to see saved apps."
    case .duplicateApp(let name):
      return "A saved app named “\(name)” already exists. Pass --force to replace it."
    case .invalidBundleIdentifier(let value):
      return
        "“\(value)” is not a valid bundle identifier. Use reverse-DNS form, for example com.example.MyApp."
    case .setupProblem(let message):
      return message
    case .missingFile(let path):
      return "No file exists at \(path)."
    case .notADirectory(let path):
      return "\(path) already exists and is not a directory."
    case .cannotCreateDirectory(let path, let reason):
      return "Could not create \(path): \(reason)"
    case .notAnAppBundlePath(let path):
      return "\(path) does not end in .app. Saved paths point at a built app bundle."
    case .pathNotFound(let name):
      return "No saved path named \u{201C}\(name)\u{201D}. Run `simbuddy paths list` to see saved paths."
    case .duplicatePath(let name):
      return "A saved path named \u{201C}\(name)\u{201D} already exists. Pass --force to replace it."
    case .recordingAlreadyRunning(let path):
      return "A recording is already running, writing to \(path). Stop it before starting another."
    case .noRecordingRunning:
      return "No recording is running."
    case .recordingFailed(let message):
      return "Recording failed: \(message)"
    case .invalidImportFile(let message):
      return "Could not read that deep-link file: \(message)"
    case .missingLinkScheme:
      return
        "This link uses $scheme, so it needs an app to open on. Pass --app, or save an app scheme with `simbuddy bundles add <name> <bundle-id> --scheme <scheme>`."
    case .missingLinkParameter(let name):
      return "This link needs a value for $\(name). Pass --set \(name)=<value>."
    case .appHasNoScheme(let name):
      return
        "Saved app \u{201C}\(name)\u{201D} has no scheme. Add one with `simbuddy bundles add \(name) <bundle-id> --scheme <scheme> --force`."
    case .noSchemeForLink(let name):
      return
        "No saved app with a scheme can open \u{201C}\(name)\u{201D}. Add one with `simbuddy bundles add <name> <bundle-id> --scheme <scheme>`."
    case .appNotInstalled(let identifier, let device):
      return "\(identifier) is not installed on \(device)."
    case .appNotRunning(let identifier, let device):
      return "\(identifier) is not running on \(device)."
    case .unsupportedAction(let capability, let kind):
      return "\(kind.label)s cannot do that. \(capability.unavailableReason(for: kind))"
    case .wrongBuildForDevice(let name, let kind, let hint):
      return "\(name) cannot be installed on a \(kind.label.lowercased()). \(hint)"
    case .devicectlUnavailable:
      return
        "devicectl is not available. Physical devices need Xcode 15 or newer; run `simbuddy doctor`."
    case .invalidAssignment(let value):
      return "\u{201C}\(value)\u{201D} is not a name=value pair. Write --set slot=staging5."
    case .invalidScheme(let value):
      return
        "\u{201C}\(value)\u{201D} is not a valid URL scheme. Use letters, digits, +, -, and . starting with a letter."
    case .networkFailed(let message):
      return "Could not reach Firebase: \(message)"
    case .noFirebaseCredential:
      return """
        No Google credential found. SimctlBuddy can use any one of these:
          • a service account key, at GOOGLE_APPLICATION_CREDENTIALS or \
        `simbuddy config set firebase-service-account <path>`
          • the gcloud CLI, after `gcloud auth login`
          • the Firebase CLI, after `firebase login`
          • an access token in SIMBUDDY_FIREBASE_TOKEN
        """
    case .invalidServiceAccount(let message):
      return "That service account key cannot be used: \(message)"
    case .firebaseAccessDenied(let message):
      return message
    case .invalidFirebaseAppID(let value):
      return
        "\u{201C}\(value)\u{201D} is not a Firebase iOS app ID. They look like 1:1234567890:ios:abc123, and are on the app's page in the Firebase console."
    case .duplicateFirebaseApp(let name):
      return "A Firebase app called \u{201C}\(name)\u{201D} is already saved. Pass --force to replace it."
    case .firebaseAppNotFound(let name):
      return "No saved Firebase app called \u{201C}\(name)\u{201D}. Run `simbuddy firebase apps` to see them."
    case .firebaseNeedsPhysicalDevice:
      return
        "App Distribution builds are signed iOS binaries, so they only install on a physical device. Simulators need a simulator build installed with `simbuddy install`."
    case .releaseHasNoBinary(let version):
      return "\(version) has no downloadable binary. It may still be processing, or it may have expired."
    case .invalidArchive(let message):
      return message
    case .deviceNotInProfile(let release, let device, let profile, let deviceCount):
      return """
        \(release) is not signed for \(device).
        Its profile (\(profile)) lists \(deviceCount) device\(deviceCount == 1 ? "" : "s"), and this one is not among them.
        An ad hoc build only installs on devices registered before it was built, so this needs a rebuild \
        with the device added. Pass --force to try anyway.
        """
    }
  }
}
