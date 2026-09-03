import Foundation

/// A Firebase app registered in a project.
public struct FirebaseApp: Codable, Equatable, Sendable {
  /// The App Distribution identifier, shaped `1:<projectNumber>:ios:<hash>`.
  public let appID: String
  public let displayName: String
  public let bundleIdentifier: String?

  public init(appID: String, displayName: String, bundleIdentifier: String? = nil) {
    self.appID = appID
    self.displayName = displayName
    self.bundleIdentifier = bundleIdentifier
  }

  /// The project number is the middle field of the app identifier, so a saved
  /// app identifier is enough to address the API without a second lookup.
  public var projectNumber: String? {
    let parts = appID.split(separator: ":")
    guard parts.count >= 3, !parts[1].isEmpty else { return nil }
    return String(parts[1])
  }

  public var resourceName: String? {
    guard let projectNumber else { return nil }
    return "projects/\(projectNumber)/apps/\(appID)"
  }

  public static func validate(_ appID: String) throws -> String {
    let trimmed = appID.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ":")
    guard parts.count >= 4, parts[0] == "1", !parts[1].isEmpty, parts[2] == "ios" else {
      throw SimctlBuddyError.invalidFirebaseAppID(trimmed)
    }
    return trimmed
  }
}

/// The iOS apps in one project, or why they could not be read.
public struct FirebaseProjectApps: Sendable, Equatable {
  public let projectID: String
  public let projectName: String
  public let apps: [FirebaseApp]
  /// Set when this project refused, so a walk can report it and carry on.
  public let problem: String?

  public init(
    projectID: String,
    projectName: String,
    apps: [FirebaseApp],
    problem: String? = nil
  ) {
    self.projectID = projectID
    self.projectName = projectName
    self.apps = apps
    self.problem = problem
  }

  public var isReadable: Bool { problem == nil }
}

/// One build in App Distribution.
public struct FirebaseRelease: Equatable, Sendable {
  public let name: String
  public let displayVersion: String
  public let buildVersion: String
  public let releaseNotes: String?
  public let createTime: Date?
  public let binaryDownloadURI: String?
  public let binaryType: String?

  public init(
    name: String,
    displayVersion: String,
    buildVersion: String,
    releaseNotes: String? = nil,
    createTime: Date? = nil,
    binaryDownloadURI: String? = nil,
    binaryType: String? = nil
  ) {
    self.name = name
    self.displayVersion = displayVersion
    self.buildVersion = buildVersion
    self.releaseNotes = releaseNotes
    self.createTime = createTime
    self.binaryDownloadURI = binaryDownloadURI
    self.binaryType = binaryType
  }

  /// The last path component of the resource name, which is what a person would
  /// type to pick this release again.
  public var releaseID: String {
    String(name.split(separator: "/").last ?? "")
  }

  public var versionLabel: String {
    buildVersion.isEmpty ? displayVersion : "\(displayVersion) (\(buildVersion))"
  }

  /// The most useful single line of the release notes.
  ///
  /// CI commonly writes a whole commit log, opening with a `# Version:` heading
  /// that only repeats what the version label already says. Skipping headings
  /// and list markers finds the line a person would actually read.
  public var summaryLine: String? {
    guard let releaseNotes else { return nil }
    for raw in releaseNotes.split(separator: "\n", omittingEmptySubsequences: true) {
      var line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      if line.hasPrefix("- ") || line.hasPrefix("* ") { line.removeFirst(2) }
      // Trailing "(sha) [Author]" is noise in a one-line summary.
      if let range = line.range(of: " - (", options: .backwards) {
        line = String(line[line.startIndex..<range.lowerBound])
      }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return trimmed }
    }
    return nil
  }

  /// A file name that says which build it is, for the download cache.
  public var suggestedFileName: String {
    let safe = versionLabel.replacingOccurrences(
      of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
    return "\(safe)-\(releaseID).ipa"
  }
}

/// Reads App Distribution over its REST API.
///
/// There is no command line tool that lists or downloads releases — the Firebase
/// CLI only uploads — so this talks to the API directly rather than shelling
/// out the way the rest of the package does.
public struct FirebaseClient: Sendable {
  public static let scope = "https://www.googleapis.com/auth/cloud-platform"

  private static let distributionHost = "https://firebaseappdistribution.googleapis.com/v1"
  private static let managementHost = "https://firebase.googleapis.com/v1beta1"

  private let http: any HTTPRequesting
  private let credentials: FirebaseCredentials

  public init(
    http: any HTTPRequesting = URLSessionRequester(),
    credentials: FirebaseCredentials? = nil
  ) {
    self.http = http
    self.credentials = credentials ?? FirebaseCredentials(http: http)
  }

  public func token() throws -> FirebaseToken {
    try credentials.token()
  }

  public func availableCredentialSources() -> [String] {
    credentials.availableSources()
  }

  // MARK: - Projects and apps

  public func projects(token: FirebaseToken? = nil) throws -> [(id: String, name: String)] {
    let token = try token ?? credentials.token()
    var found: [(id: String, name: String)] = []
    var pageToken: String?
    repeat {
      let response = try send(
        HTTPRequest(url: url("\(Self.managementHost)/projects", page: pageToken)),
        token: token,
        quotaProject: nil,
        reading: "your Firebase projects"
      )
      guard let payload = try? JSONDecoder().decode(ProjectListResponse.self, from: response.body)
      else { throw SimctlBuddyError.invalidResponse("The project list was not what was expected.") }
      found += payload.results.map { ($0.projectId, $0.displayName ?? $0.projectId) }
      pageToken = payload.nextPageToken
    } while pageToken != nil
    return found
  }

  public func iosApps(projectID: String, token: FirebaseToken? = nil) throws -> [FirebaseApp] {
    let token = try token ?? credentials.token()
    var found: [FirebaseApp] = []
    var pageToken: String?
    repeat {
      let response = try send(
        HTTPRequest(
          url: url("\(Self.managementHost)/projects/\(projectID)/iosApps", page: pageToken)),
        token: token,
        quotaProject: projectID,
        reading: "the iOS apps in \(projectID)"
      )
      guard let payload = try? JSONDecoder().decode(IOSAppListResponse.self, from: response.body)
      else { throw SimctlBuddyError.invalidResponse("The app list was not what was expected.") }
      found += payload.apps.map {
        FirebaseApp(
          appID: $0.appId,
          displayName: $0.displayName ?? $0.bundleId ?? $0.appId,
          bundleIdentifier: $0.bundleId
        )
      }
      pageToken = payload.nextPageToken
    } while pageToken != nil
    return found
  }

  /// Every iOS app in every project this credential can see.
  ///
  /// One project refusing must not end the walk: access is granted per project,
  /// so a partial answer is the normal case rather than an error. The token is
  /// fetched once and reused, because obtaining one costs a round trip of its
  /// own and this makes a call per project.
  public func allIOSApps() throws -> [FirebaseProjectApps] {
    let token = try credentials.token()
    return try projects(token: token).map { project in
      do {
        return FirebaseProjectApps(
          projectID: project.id,
          projectName: project.name,
          apps: try iosApps(projectID: project.id, token: token)
        )
      } catch {
        return FirebaseProjectApps(
          projectID: project.id,
          projectName: project.name,
          apps: [],
          problem: Self.firstLine(of: error.localizedDescription)
        )
      }
    }
  }

  private static func firstLine(of message: String) -> String {
    message.split(separator: "\n").first.map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? message
  }

  // MARK: - Releases

  /// Builds for an app, newest first.
  ///
  /// `filter` is passed through to the API, which understands `displayVersion`,
  /// `buildVersion` and `releaseNotes.text` with `*` wildcards.
  public func releases(
    appID: String,
    limit: Int = 50,
    filter: String? = nil,
    token: FirebaseToken? = nil
  ) throws -> [FirebaseRelease] {
    let identifier = try FirebaseApp.validate(appID)
    let app = FirebaseApp(appID: identifier, displayName: identifier)
    guard let parent = app.resourceName, let projectNumber = app.projectNumber else {
      throw SimctlBuddyError.invalidFirebaseAppID(identifier)
    }
    let token = try token ?? credentials.token()

    var components = URLComponents(string: "\(Self.distributionHost)/\(parent)/releases")!
    var query = [
      URLQueryItem(name: "pageSize", value: String(min(max(limit, 1), 100))),
      URLQueryItem(name: "orderBy", value: "createTime desc"),
    ]
    if let filter, !filter.trimmingCharacters(in: .whitespaces).isEmpty {
      query.append(URLQueryItem(name: "filter", value: filter))
    }
    components.queryItems = query

    let response = try send(
      HTTPRequest(url: components.url!),
      token: token,
      quotaProject: projectNumber,
      reading: "this app's builds"
    )
    guard let payload = try? JSONDecoder().decode(ReleaseListResponse.self, from: response.body)
    else {
      throw SimctlBuddyError.invalidResponse("The release list was not what was expected.")
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()

    return payload.releases.map { release in
      FirebaseRelease(
        name: release.name,
        displayVersion: release.displayVersion ?? "",
        buildVersion: release.buildVersion ?? "",
        releaseNotes: release.releaseNotes?.text,
        createTime: release.createTime.flatMap {
          formatter.date(from: $0) ?? plain.date(from: $0)
        },
        binaryDownloadURI: release.binaryDownloadUri,
        binaryType: release.binaryType
      )
    }
  }

  /// Downloads a release's binary.
  ///
  /// The download link is signed and short-lived, so it is fetched fresh from
  /// the release rather than stored, and it carries no authorization header of
  /// its own.
  public func download(_ release: FirebaseRelease, to destination: URL) throws {
    guard let uri = release.binaryDownloadURI, let url = URL(string: uri) else {
      throw SimctlBuddyError.releaseHasNoBinary(release.versionLabel)
    }
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try http.download(HTTPRequest(url: url), to: destination)
  }

  // MARK: - Request plumbing

  private func url(_ string: String) -> URL {
    URL(string: string)!
  }

  /// One page of a list endpoint. A hundred is the largest page these accept,
  /// so this is the fewest round trips the walk can take.
  private func url(_ string: String, page: String?) -> URL {
    var components = URLComponents(string: string)!
    components.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
      + (page.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
    return components.url!
  }

  /// Adds authorization, and the quota project a bare user credential needs.
  ///
  /// Without `x-goog-user-project`, Google refuses such credentials with a 403
  /// about an unset quota project, which reads like a permissions problem and
  /// is not one. Naming a project has the opposite failure: the header needs
  /// `serviceusage.services.use` on it, which a tester invited to someone
  /// else's project does not have, and the project reads fine without it. So
  /// the header is dropped and the call retried when that is what refused it —
  /// otherwise every project shared with you looks unreadable.
  private func send(
    _ request: HTTPRequest,
    token: FirebaseToken,
    quotaProject: String?,
    reading: String
  ) throws -> HTTPResponse {
    let authorized = request.adding("Authorization", "Bearer \(token.accessToken)")
    let named = token.needsQuotaProject && quotaProject != nil
    let prepared =
      named ? authorized.adding("x-goog-user-project", quotaProject!) : authorized

    var response = try http.perform(prepared)
    if named, Self.isQuotaProjectRefusal(response) {
      response = try http.perform(authorized)
    }
    guard response.isSuccess else {
      throw Self.error(from: response, source: token.source, reading: reading)
    }
    return response
  }

  /// A 403 about using the named project, rather than about the thing asked
  /// for. Only this shape is worth retrying without the header.
  static func isQuotaProjectRefusal(_ response: HTTPResponse) -> Bool {
    guard response.statusCode == 403 else { return false }
    let message = FirebaseCredentials.errorText(response).lowercased()
    return message.contains("permission to use project") || message.contains("serviceusage")
  }

  /// Turns Google's 403s into the four different problems they actually are.
  /// `reading` names what was being fetched, so a refusal says which thing was
  /// out of reach rather than always blaming the release list.
  static func error(
    from response: HTTPResponse,
    source: FirebaseToken.Source,
    reading: String = "this project's releases"
  ) -> SimctlBuddyError {
    let message = FirebaseCredentials.errorText(response)
    let lowered = message.lowercased()

    if response.statusCode == 401 {
      return .firebaseAccessDenied(
        "The credential from \(source.label) was rejected. It may have expired — sign in again.")
    }
    if lowered.contains("quota project") {
      return .firebaseAccessDenied(
        """
        The credential from \(source.label) needs a quota project.
        Run `gcloud auth application-default set-quota-project <projectId>`, \
        or use a service account key instead.
        """)
    }
    if lowered.contains("has not been used") || lowered.contains("is disabled")
      || lowered.contains("service_disabled")
    {
      return .firebaseAccessDenied(
        """
        The App Distribution API is not enabled on this project.
        Enable firebaseappdistribution.googleapis.com in the Google Cloud console, \
        or open App Distribution in the Firebase console and click Get started.
        """)
    }
    if isQuotaProjectRefusal(response) {
      return .firebaseAccessDenied(
        """
        \(source.label) may not bill quota to this project.
        It needs the Service Usage Consumer role there, or sign in with the \
        Firebase CLI instead — `firebase login` — which brings its own quota project.
        """)
    }
    if response.statusCode == 403 {
      return .firebaseAccessDenied(
        """
        \(source.label) is not allowed to read \(reading).
        It needs the Firebase App Distribution Viewer role on that project. Being a tester is not enough.
        """)
    }
    if response.statusCode == 404 {
      return .firebaseAccessDenied(
        "No such app in App Distribution. Check the app ID, and that a build has been uploaded.")
    }
    return .firebaseAccessDenied(message)
  }
}

// MARK: - Wire formats

/// An app with no releases omits the array entirely rather than sending an
/// empty one, so every collection here decodes as optional and reads as empty.
private struct ReleaseListResponse: Decodable {
  struct Notes: Decodable {
    let text: String?
  }
  struct Release: Decodable {
    let name: String
    let displayVersion: String?
    let buildVersion: String?
    let releaseNotes: Notes?
    let createTime: String?
    let binaryDownloadUri: String?
    let binaryType: String?
  }

  private let releaseList: [Release]?
  var releases: [Release] { releaseList ?? [] }

  enum CodingKeys: String, CodingKey {
    case releaseList = "releases"
  }
}

private struct ProjectListResponse: Decodable {
  struct Project: Decodable {
    let projectId: String
    let displayName: String?
  }

  private let resultList: [Project]?
  let nextPageToken: String?
  var results: [Project] { resultList ?? [] }

  enum CodingKeys: String, CodingKey {
    case resultList = "results"
    case nextPageToken
  }
}

private struct IOSAppListResponse: Decodable {
  struct App: Decodable {
    let appId: String
    let displayName: String?
    let bundleId: String?
  }

  private let appList: [App]?
  let nextPageToken: String?
  var apps: [App] { appList ?? [] }

  enum CodingKeys: String, CodingKey {
    case appList = "apps"
    case nextPageToken
  }
}
