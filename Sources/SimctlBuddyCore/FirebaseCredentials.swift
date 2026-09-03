import Foundation
import Security

/// An access token plus where it came from.
///
/// The source matters at call time, not only for diagnostics: Google rejects
/// user credentials against the App Distribution API unless the request also
/// names a project to bill the quota to. Service accounts carry their own.
public struct FirebaseToken: Sendable, Equatable {
  public enum Source: Equatable, Sendable {
    case environment
    case serviceAccount(email: String)
    case gcloud
    case firebaseCLI

    public var label: String {
      switch self {
      case .environment: return "SIMBUDDY_FIREBASE_TOKEN"
      case .serviceAccount(let email): return "service account \(email)"
      case .gcloud: return "gcloud"
      case .firebaseCLI: return "the Firebase CLI"
      }
    }
  }

  public let accessToken: String
  public let source: Source

  public init(accessToken: String, source: Source) {
    self.accessToken = accessToken
    self.source = source
  }

  /// A service account bills quota to its own project, and the Firebase CLI's
  /// OAuth client carries one of its own, so neither has to name a project.
  ///
  /// The rest are bare user credentials that do. Naming one is not free:
  /// `x-goog-user-project` needs `serviceusage.services.use` on that project,
  /// which a tester on someone else's project usually lacks, so the header
  /// turns a readable project into a 403. `FirebaseClient` retries without it.
  public var needsQuotaProject: Bool {
    switch source {
    case .serviceAccount, .firebaseCLI: return false
    case .environment, .gcloud: return true
    }
  }
}

/// Finds a Google credential without asking the user to set one up if their
/// machine already has one.
///
/// Sources are tried in order and the first that produces a token wins. Nothing
/// here ever opens a browser: SimctlBuddy does not own an OAuth client, and the
/// scope this needs is one Google gates behind app verification.
public struct FirebaseCredentials: Sendable {
  public static let tokenEnvironmentKey = "SIMBUDDY_FIREBASE_TOKEN"
  public static let serviceAccountEnvironmentKey = "GOOGLE_APPLICATION_CREDENTIALS"

  private let http: any HTTPRequesting
  private let runner: any CommandRunning
  private let environment: [String: String]
  private let settingsStore: SettingsStore

  public init(
    http: any HTTPRequesting = URLSessionRequester(),
    runner: any CommandRunning = ProcessRunner(),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    settingsStore: SettingsStore = SettingsStore()
  ) {
    self.http = http
    self.runner = runner
    self.environment = environment
    self.settingsStore = settingsStore
  }

  /// The first credential that works, or an error naming every way to supply one.
  public func token() throws -> FirebaseToken {
    if let raw = trimmed(environment[Self.tokenEnvironmentKey]) {
      return FirebaseToken(accessToken: raw, source: .environment)
    }
    if let path = try serviceAccountPath() {
      return try serviceAccountToken(atPath: path)
    }
    if let token = gcloudToken() {
      return token
    }
    if let token = firebaseCLIToken() {
      return token
    }
    throw SimctlBuddyError.noFirebaseCredential
  }

  /// Which sources are present, for `doctor`. Does not fetch a token.
  public func availableSources() -> [String] {
    var found = [String]()
    if trimmed(environment[Self.tokenEnvironmentKey]) != nil {
      found.append("\(Self.tokenEnvironmentKey) is set")
    }
    if let path = (try? serviceAccountPath()) ?? nil {
      found.append("service account key at \(path)")
    }
    if executablePath(for: "gcloud") != nil { found.append("gcloud is installed") }
    // The config file exists as soon as the CLI runs once, so its presence says
    // nothing. Only a stored refresh token means signed in — claiming otherwise
    // contradicts the "no credential" error that follows.
    if storedFirebaseRefreshToken() != nil {
      found.append("the Firebase CLI is signed in")
    } else if executablePath(for: "firebase") != nil {
      found.append("the Firebase CLI is installed but not signed in — run `firebase login`")
    }
    return found
  }

  // MARK: - Service account

  private func serviceAccountPath() throws -> String? {
    if let configured = trimmed(try? settingsStore.load().firebaseServiceAccount) {
      return SettingsStore.absolutePath(configured)
    }
    if let fromEnvironment = trimmed(environment[Self.serviceAccountEnvironmentKey]) {
      return SettingsStore.absolutePath(fromEnvironment)
    }
    return nil
  }

  private func serviceAccountToken(atPath path: String) throws -> FirebaseToken {
    guard let data = FileManager.default.contents(atPath: path) else {
      throw SimctlBuddyError.invalidServiceAccount("No file at \(path).")
    }
    let key: ServiceAccountKey
    do {
      key = try JSONDecoder().decode(ServiceAccountKey.self, from: data)
    } catch {
      throw SimctlBuddyError.invalidServiceAccount(
        "\(path) is not a Google service account key file.")
    }

    let assertion = try key.signedAssertion(scope: FirebaseClient.scope)
    var body = URLComponents()
    body.queryItems = [
      URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
      URLQueryItem(name: "assertion", value: assertion),
    ]
    let response = try http.perform(
      HTTPRequest(
        url: URL(string: "https://oauth2.googleapis.com/token")!,
        method: "POST",
        headers: ["Content-Type": "application/x-www-form-urlencoded"],
        body: Data((body.percentEncodedQuery ?? "").utf8)
      ))
    guard response.isSuccess else {
      throw SimctlBuddyError.invalidServiceAccount(
        "Google refused the key for \(key.clientEmail): \(Self.errorText(response))")
    }
    guard
      let payload = try? JSONDecoder().decode(TokenResponse.self, from: response.body)
    else {
      throw SimctlBuddyError.invalidServiceAccount("Google returned a token that made no sense.")
    }
    return FirebaseToken(
      accessToken: payload.accessToken,
      source: .serviceAccount(email: key.clientEmail)
    )
  }

  // MARK: - Installed command line tools

  private func gcloudToken() -> FirebaseToken? {
    guard let path = executablePath(for: "gcloud") else { return nil }
    guard
      let result = try? runner.run(executable: path, arguments: ["auth", "print-access-token"]),
      result.exitCode == 0,
      let token = trimmed(result.standardOutput)
    else { return nil }
    return FirebaseToken(accessToken: token, source: .gcloud)
  }

  /// The Firebase CLI keeps a refresh token in its config file. Exchanging it
  /// needs that tool's own OAuth client, which is a published constant in its
  /// repository rather than a secret, and which it lets you override the same
  /// way.
  private func firebaseCLIToken() -> FirebaseToken? {
    guard let refreshToken = storedFirebaseRefreshToken() else { return nil }

    let clientID =
      trimmed(environment["FIREBASE_CLIENT_ID"])
      ?? "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
    let clientSecret =
      trimmed(environment["FIREBASE_CLIENT_SECRET"]) ?? "j9iVZfS8kkCEFUPaAeJV0sAi"

    var body = URLComponents()
    body.queryItems = [
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "client_secret", value: clientSecret),
    ]
    guard
      let response = try? http.perform(
        HTTPRequest(
          url: URL(string: "https://oauth2.googleapis.com/token")!,
          method: "POST",
          headers: ["Content-Type": "application/x-www-form-urlencoded"],
          body: Data((body.percentEncodedQuery ?? "").utf8)
        )),
      response.isSuccess,
      let payload = try? JSONDecoder().decode(TokenResponse.self, from: response.body)
    else { return nil }
    return FirebaseToken(accessToken: payload.accessToken, source: .firebaseCLI)
  }

  /// The refresh token the Firebase CLI stored at `firebase login`, if there is
  /// one. An empty `{}` config means the CLI has run but nobody has signed in.
  private func storedFirebaseRefreshToken() -> String? {
    guard
      let data = try? Data(contentsOf: Self.firebaseConfigURL),
      let config = try? JSONDecoder().decode(FirebaseCLIConfig.self, from: data)
    else { return nil }
    return trimmed(config.tokens?.refreshToken)
  }

  private static var firebaseConfigURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/configstore/firebase-tools.json")
  }

  // MARK: - Helpers

  private func executablePath(for name: String) -> String? {
    let candidates = [
      "/opt/homebrew/bin/\(name)",
      "/usr/local/bin/\(name)",
      "/usr/bin/\(name)",
    ]
    if let known = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
      return known
    }
    guard
      let result = try? runner.run(executable: "/usr/bin/which", arguments: [name]),
      result.exitCode == 0,
      let path = trimmed(result.standardOutput),
      FileManager.default.isExecutableFile(atPath: path)
    else { return nil }
    return path
  }

  private func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  /// Google speaks two error shapes: the API envelope, and OAuth's flat form
  /// from the token endpoint. Reading both keeps raw JSON off the screen.
  static func errorText(_ response: HTTPResponse) -> String {
    if let error = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: response.body),
      !error.error.message.isEmpty
    {
      return error.error.message
    }
    if let oauth = try? JSONDecoder().decode(OAuthErrorEnvelope.self, from: response.body) {
      let description = oauth.errorDescription?.trimmingCharacters(in: .whitespaces) ?? ""
      if !description.isEmpty { return description }
      if let code = oauth.error, !code.isEmpty { return code }
    }
    let raw = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty ? "HTTP \(response.statusCode)" : raw
  }
}

// MARK: - Wire formats

private struct TokenResponse: Decodable {
  let accessToken: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
  }
}

private struct FirebaseCLIConfig: Decodable {
  struct Tokens: Decodable {
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
      case refreshToken = "refresh_token"
    }
  }
  let tokens: Tokens?
}

/// The token endpoint's error shape, which is flat rather than nested.
struct OAuthErrorEnvelope: Decodable {
  let error: String?
  let errorDescription: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescription = "error_description"
  }
}

struct GoogleErrorEnvelope: Decodable {
  struct Payload: Decodable {
    let message: String
    let status: String?
  }
  let error: Payload
}

/// The parts of a service account key file that matter for signing.
struct ServiceAccountKey: Decodable {
  let clientEmail: String
  let privateKey: String
  let tokenURI: String?

  enum CodingKeys: String, CodingKey {
    case clientEmail = "client_email"
    case privateKey = "private_key"
    case tokenURI = "token_uri"
  }

  /// Builds and signs the JWT Google exchanges for an access token.
  func signedAssertion(scope: String, now: Date = Date()) throws -> String {
    let issuedAt = Int(now.timeIntervalSince1970)
    let header = ["alg": "RS256", "typ": "JWT"]
    let claims: [String: Any] = [
      "iss": clientEmail,
      "scope": scope,
      "aud": tokenURI ?? "https://oauth2.googleapis.com/token",
      "iat": issuedAt,
      "exp": issuedAt + 3600,
    ]

    let encodedHeader = try Self.base64URL(JSONSerialization.data(withJSONObject: header))
    let encodedClaims = try Self.base64URL(
      JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
    let signingInput = "\(encodedHeader).\(encodedClaims)"
    let signature = try sign(Data(signingInput.utf8))
    return "\(signingInput).\(Self.base64URL(signature))"
  }

  private func sign(_ data: Data) throws -> Data {
    let key = try secKey()
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &error) as Data?
    else {
      let reason = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String }
      throw SimctlBuddyError.invalidServiceAccount(
        "Signing with the key for \(clientEmail) failed: \(reason ?? "unknown reason")")
    }
    return signature
  }

  private func secKey() throws -> SecKey {
    let der = try Self.pkcs1(from: privateKey)
    var error: Unmanaged<CFError>?
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
    ]
    guard
      let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error)
    else {
      let reason = (error?.takeRetainedValue()).map { CFErrorCopyDescription($0) as String }
      throw SimctlBuddyError.invalidServiceAccount(
        "The private key could not be read: \(reason ?? "unknown reason")")
    }
    return key
  }

  /// Service account keys are PEM-wrapped PKCS#8. `SecKeyCreateWithData` wants
  /// the bare PKCS#1 key inside, so the wrapper has to come off.
  static func pkcs1(from pem: String) throws -> Data {
    let base64 =
      pem
      .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
      .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
      .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
      .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
      .components(separatedBy: .whitespacesAndNewlines)
      .joined()
    guard !base64.isEmpty, let der = Data(base64Encoded: base64) else {
      throw SimctlBuddyError.invalidServiceAccount("The private key is not valid PEM.")
    }
    // An RSA PRIVATE KEY block is already PKCS#1.
    if pem.contains("BEGIN RSA PRIVATE KEY") { return der }
    return try unwrapPKCS8(der)
  }

  /// Walks just enough DER to reach the octet string holding the PKCS#1 key:
  /// SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING key }.
  private static func unwrapPKCS8(_ der: Data) throws -> Data {
    var reader = DERReader(der)
    guard
      let outer = reader.readSequence(),
      var inner = Optional(DERReader(outer)),
      inner.skipElement(),  // version
      inner.skipElement(),  // algorithm identifier
      let key = inner.readElement(tag: 0x04)
    else {
      throw SimctlBuddyError.invalidServiceAccount(
        "The private key is not in the expected PKCS#8 format.")
    }
    return key
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// The smallest DER reader that can find a key inside a PKCS#8 wrapper.
private struct DERReader {
  private let bytes: [UInt8]
  private var offset = 0

  init(_ data: Data) {
    self.bytes = [UInt8](data)
  }

  mutating func readSequence() -> Data? {
    readElement(tag: 0x30)
  }

  mutating func readElement(tag: UInt8) -> Data? {
    guard offset < bytes.count, bytes[offset] == tag else { return nil }
    offset += 1
    guard let length = readLength() else { return nil }
    guard offset + length <= bytes.count else { return nil }
    let value = Data(bytes[offset..<(offset + length)])
    offset += length
    return value
  }

  mutating func skipElement() -> Bool {
    guard offset < bytes.count else { return false }
    offset += 1
    guard let length = readLength(), offset + length <= bytes.count else { return false }
    offset += length
    return true
  }

  private mutating func readLength() -> Int? {
    guard offset < bytes.count else { return nil }
    let first = bytes[offset]
    offset += 1
    if first < 0x80 { return Int(first) }
    let count = Int(first & 0x7F)
    guard count > 0, count <= 4, offset + count <= bytes.count else { return nil }
    var length = 0
    for _ in 0..<count {
      length = (length << 8) | Int(bytes[offset])
      offset += 1
    }
    return length
  }
}
