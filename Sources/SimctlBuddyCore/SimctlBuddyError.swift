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

  public var errorDescription: String? {
    switch self {
    case .commandFailed(let command, let exitCode, let message):
      return "Command failed (\(exitCode)): \(command)\n\(message)"
    case .invalidResponse(let message):
      return "Could not understand simctl output: \(message)"
    case .noBootedDevice:
      return "No iOS Simulator is booted. Run `simbuddy boot` first."
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
    }
  }
}
