import Foundation
import Security
import XCTest

@testable import SimctlBuddyCore
@testable import SimctlBuddyTUI

final class FirebaseAppTests: XCTestCase {
  func testProjectNumberComesFromTheAppIdentifier() {
    let app = FirebaseApp(appID: "1:1234567890:ios:abc123", displayName: "Demo")
    XCTAssertEqual(app.projectNumber, "1234567890")
    XCTAssertEqual(app.resourceName, "projects/1234567890/apps/1:1234567890:ios:abc123")
  }

  func testValidateAcceptsAnIOSAppIdentifier() throws {
    XCTAssertEqual(
      try FirebaseApp.validate("  1:1234567890:ios:abc123  "),
      "1:1234567890:ios:abc123"
    )
  }

  func testValidateRejectsAndroidAndNonsense() {
    XCTAssertThrowsError(try FirebaseApp.validate("1:1234567890:android:abc"))
    XCTAssertThrowsError(try FirebaseApp.validate("not-an-app-id"))
    XCTAssertThrowsError(try FirebaseApp.validate("1:1234567890:ios"))
    XCTAssertThrowsError(try FirebaseApp.validate(""))
  }
}

final class FirebaseReleaseTests: XCTestCase {
  private func release(display: String, build: String, name: String) -> FirebaseRelease {
    FirebaseRelease(name: name, displayVersion: display, buildVersion: build)
  }

  func testReleaseIDIsTheLastPathComponent() {
    let subject = release(
      display: "1.2.0", build: "88",
      name: "projects/1234/apps/1:1234:ios:abc/releases/xyz789")
    XCTAssertEqual(subject.releaseID, "xyz789")
  }

  func testVersionLabelCombinesBothVersions() {
    XCTAssertEqual(release(display: "1.2.0", build: "88", name: "a/b").versionLabel, "1.2.0 (88)")
  }

  func testVersionLabelFallsBackWhenThereIsNoBuildNumber() {
    XCTAssertEqual(release(display: "1.2.0", build: "", name: "a/b").versionLabel, "1.2.0")
  }

  func testSuggestedFileNameIsSafeForTheFileSystem() {
    let subject = release(
      display: "1.2.0/beta", build: "88", name: "projects/x/releases/id1")
    XCTAssertFalse(subject.suggestedFileName.contains("/"))
    XCTAssertTrue(subject.suggestedFileName.hasSuffix(".ipa"))
  }
}

final class ProvisioningProfileTests: XCTestCase {
  private let deviceUDID = "00008101-000A0C123456001E"

  func testAdHocProfilePermitsARegisteredDevice() {
    let profile = ProvisioningProfile(provisionedDevices: [deviceUDID, "other"])
    XCTAssertTrue(profile.permits(hardwareUDID: deviceUDID))
  }

  func testAdHocProfileRefusesAnUnregisteredDevice() {
    let profile = ProvisioningProfile(provisionedDevices: ["someone-else"])
    XCTAssertFalse(profile.permits(hardwareUDID: deviceUDID))
  }

  func testUDIDMatchingIgnoresCase() {
    let profile = ProvisioningProfile(provisionedDevices: [deviceUDID.lowercased()])
    XCTAssertTrue(profile.permits(hardwareUDID: deviceUDID.uppercased()))
  }

  func testEnterpriseProfilePermitsAnyDevice() {
    let profile = ProvisioningProfile(provisionsAllDevices: true, provisionedDevices: [])
    XCTAssertTrue(profile.permits(hardwareUDID: deviceUDID))
  }

  /// An unknown UDID is not evidence the build will fail, so it is let through
  /// rather than blocked on a guess.
  func testAnUnknownDeviceUDIDIsNotBlocked() {
    let profile = ProvisioningProfile(provisionedDevices: ["someone-else"])
    XCTAssertTrue(profile.permits(hardwareUDID: nil))
    XCTAssertTrue(profile.permits(hardwareUDID: ""))
  }

  func testAProfileWithNoDeviceListIsNotTreatedAsRefusing() {
    let profile = ProvisioningProfile(provisionedDevices: [])
    XCTAssertTrue(profile.permits(hardwareUDID: deviceUDID))
  }

  func testExpiryIsReadFromTheDate() {
    let past = ProvisioningProfile(expirationDate: Date(timeIntervalSinceNow: -60))
    let future = ProvisioningProfile(expirationDate: Date(timeIntervalSinceNow: 60))
    XCTAssertTrue(past.isExpired)
    XCTAssertFalse(future.isExpired)
    XCTAssertFalse(ProvisioningProfile().isExpired)
  }
}

final class FirebaseErrorMappingTests: XCTestCase {
  private func error(_ status: Int, _ message: String) -> SimctlBuddyError {
    let body = Data(#"{"error":{"message":"\#(message)","status":"PERMISSION_DENIED"}}"#.utf8)
    return FirebaseClient.error(
      from: HTTPResponse(statusCode: status, body: body),
      source: .gcloud
    )
  }

  func testQuotaProjectIsCalledOutSeparatelyFromPermissions() {
    let description = error(403, "requires a quota project, which is not set by default")
      .localizedDescription
    XCTAssertTrue(description.contains("quota project"))
    XCTAssertTrue(description.contains("set-quota-project"))
  }

  func testDisabledAPIIsCalledOutSeparately() {
    let description = error(403, "API has not been used in project 1234 before").localizedDescription
    XCTAssertTrue(description.contains("not enabled"))
    XCTAssertTrue(description.contains("firebaseappdistribution.googleapis.com"))
  }

  /// The most common real cause: someone is a tester, not a project member.
  func testPlainForbiddenExplainsTheRoleThatIsMissing() {
    let description = error(403, "The caller does not have permission").localizedDescription
    XCTAssertTrue(description.contains("Viewer role"))
    XCTAssertTrue(description.contains("tester"))
  }

  func testUnauthorizedSuggestsSigningInAgain() {
    let description = error(401, "Invalid credentials").localizedDescription
    XCTAssertTrue(description.contains("gcloud"))
    XCTAssertTrue(description.contains("expired"))
  }

  func testNotFoundMentionsTheAppIdentifier() {
    XCTAssertTrue(error(404, "not found").localizedDescription.contains("app ID"))
  }
}

final class ServiceAccountKeyTests: XCTestCase {
  /// A PKCS#8 wrapper has to come off before Security will read the key.
  func testPKCS8WrapperIsStripped() throws {
    let pkcs1 = Data([0x30, 0x03, 0x02, 0x01, 0x00])
    var pkcs8: [UInt8] = [
      0x02, 0x01, 0x00,  // version
      0x30, 0x02, 0x05, 0x00,  // algorithm identifier
      0x04, UInt8(pkcs1.count),
    ]
    pkcs8 += [UInt8](pkcs1)
    let wrapped = Data([0x30, UInt8(pkcs8.count)] + pkcs8)

    let pem = """
      -----BEGIN PRIVATE KEY-----
      \(wrapped.base64EncodedString())
      -----END PRIVATE KEY-----
      """
    XCTAssertEqual(try ServiceAccountKey.pkcs1(from: pem), pkcs1)
  }

  /// A PKCS#1 block is already what Security wants, so it passes through.
  func testRSAPrivateKeyBlockIsUsedAsIs() throws {
    let body = Data([0x30, 0x03, 0x02, 0x01, 0x00])
    let pem = """
      -----BEGIN RSA PRIVATE KEY-----
      \(body.base64EncodedString())
      -----END RSA PRIVATE KEY-----
      """
    XCTAssertEqual(try ServiceAccountKey.pkcs1(from: pem), body)
  }

  func testGarbageIsRejected() {
    XCTAssertThrowsError(try ServiceAccountKey.pkcs1(from: "not a key"))
    XCTAssertThrowsError(
      try ServiceAccountKey.pkcs1(
        from: "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----"))
  }
}

final class FirebaseStoreTests: XCTestCase {
  private var directory: URL!
  private var store: FirebaseStore!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("firebase-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    store = FirebaseStore(fileURL: directory.appendingPathComponent("firebase.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testSavingAndReadingBack() throws {
    try store.add(name: "Staging", appID: "1:1234567890:ios:abc", force: false)
    XCTAssertEqual(try store.load().map(\.name), ["Staging"])
    XCTAssertEqual(try store.app(named: "staging").appID, "1:1234567890:ios:abc")
  }

  func testDuplicateNamesNeedForce() throws {
    try store.add(name: "Staging", appID: "1:1:ios:a", force: false)
    XCTAssertThrowsError(try store.add(name: "staging", appID: "1:1:ios:b", force: false))
    try store.add(name: "staging", appID: "1:1:ios:b", force: true)
    XCTAssertEqual(try store.load().count, 1)
    XCTAssertEqual(try store.app(named: "Staging").appID, "1:1:ios:b")
  }

  /// Every command takes either a saved name or a raw identifier.
  func testResolveAcceptsBothANameAndARawIdentifier() throws {
    try store.add(name: "Staging", appID: "1:1234567890:ios:abc", force: false)
    XCTAssertEqual(try store.resolve("Staging"), "1:1234567890:ios:abc")
    XCTAssertEqual(try store.resolve("1:99:ios:zzz"), "1:99:ios:zzz")
    XCTAssertThrowsError(try store.resolve("nope"))
  }

  func testRemovingSomethingThatIsNotThereFails() {
    XCTAssertThrowsError(try store.remove(name: "ghost"))
  }

  func testAnEmptyStoreReadsAsEmpty() throws {
    XCTAssertEqual(try store.load().count, 0)
  }
}

final class FirebaseCapabilityTests: XCTestCase {
  /// App Distribution serves signed device builds, so the action must not be
  /// offered on a simulator that could never run one.
  func testOnlyPhysicalDevicesCanInstallFromAppDistribution() {
    XCTAssertTrue(DeviceKind.physical.capabilities.contains(.firebaseInstall))
    XCTAssertFalse(DeviceKind.simulator.capabilities.contains(.firebaseInstall))
  }

  func testTheRefusalExplainsWhy() {
    let reason = DeviceCapability.firebaseInstall.unavailableReason(for: .simulator)
    XCTAssertTrue(reason.contains("simulator build"))
  }
}

final class FirebaseTUIActionTests: XCTestCase {
  private let simulator = Device(
    name: "iPhone 16", udid: "S1", state: "Booted", isAvailable: true, kind: .simulator)
  private let phone = Device(
    name: "Karlo's iPhone", udid: "P1", state: "connected", isAvailable: true, kind: .physical,
    hardwareUDID: "00008101-000A0C123456001E")

  private func titles(on device: Device, apps: [SavedFirebaseApp] = []) -> [String] {
    var state = TUIState(devices: [device])
    state.firebaseApps = apps
    return state.actions.map(\.title)
  }

  /// The row would only ever fail on a simulator, so it is not offered there.
  func testTheAppDistributionRowIsHiddenOnASimulator() {
    XCTAssertFalse(titles(on: simulator).contains("Install from App Distribution"))
  }

  func testTheAppDistributionRowIsOfferedOnAPhysicalDevice() {
    XCTAssertTrue(titles(on: phone).contains("Install from App Distribution"))
  }

  /// Saving an app and checking sign-in are not device work, so they stay
  /// visible even when no device could install a build.
  func testSetupRowsSurviveOnASimulator() {
    let shown = titles(on: simulator)
    XCTAssertTrue(shown.contains("Save Firebase app ID"))
    XCTAssertTrue(shown.contains("Firebase setup \u{00B7} sign-in and steps"))
  }

  func testSavedAppsBecomeRowsOnlyWhereTheyCanBeUsed() {
    let saved = SavedFirebaseApp(name: "Staging", appID: "1:1:ios:abc")
    XCTAssertTrue(titles(on: phone, apps: [saved]).contains("☁ Staging"))
    XCTAssertFalse(titles(on: simulator, apps: [saved]).contains("☁ Staging"))
  }
}

final class ActionOrderTests: XCTestCase {
  private let simulator = Device(
    name: "iPhone 16", udid: "S1", state: "Booted", isAvailable: true, kind: .simulator)
  private let phone = Device(
    name: "Karlo's iPhone", udid: "P1", state: "connected", isAvailable: true, kind: .physical)

  /// Nothing else works until the simulator is running, so booting leads.
  func testBootAndShutDownComeFirstOnASimulator() {
    let state = TUIState(devices: [simulator])
    XCTAssertEqual(state.actions.prefix(2).map(\.id), [.boot, .shutdown])
  }

  func testTheDeviceSectionIsTheFirstHeadingDrawn() {
    let screen = TUIRenderer().render(
      state: TUIState(devices: [simulator]), columns: 120, rows: 40)
    let device = try! XCTUnwrap(screen.range(of: "DEVICE"))
    let links = try! XCTUnwrap(screen.range(of: "LINKS"))
    XCTAssertLessThan(device.lowerBound, links.lowerBound)
  }

  /// A phone has no boot state, so the section drops out rather than showing
  /// two rows that would be refused.
  func testAPhysicalDeviceStartsAtLinksInstead() {
    let state = TUIState(devices: [phone])
    XCTAssertFalse(state.actions.contains { $0.id == .boot || $0.id == .shutdown })
    XCTAssertEqual(state.actions.first?.id, .openDeepLink)
  }
}

/// The activity panel is drawn by positioning the cursor per line, so a newline
/// reaching a rendered line moves the cursor mid-frame and tears the layout
/// apart — the header vanishes and every panel below shifts.
final class MultiLineOutputTests: XCTestCase {
  func testAMultiLineMessageBecomesSeveralSingleLineEntries() {
    let lines = SimulatorTUI.entryLines("First line\nSecond line\nThird")
    XCTAssertEqual(lines, ["First line", "Second line", "Third"])
  }

  func testBlankLinesAndCarriageReturnsAreDropped() {
    XCTAssertEqual(SimulatorTUI.entryLines("a\n\n\r\nb"), ["a", "b"])
  }

  func testTabsBecomeSpaces() {
    XCTAssertFalse(SimulatorTUI.entryLines("a\tb").contains { $0.contains("\t") })
  }

  /// Several Firebase errors explain themselves over more than one line. Every
  /// one of them has to survive the trip to the screen as separate entries.
  func testEveryErrorSplitsIntoLinesWithNoControlCharacters() {
    let errors: [SimctlBuddyError] = [
      .noFirebaseCredential,
      .firebaseNeedsPhysicalDevice,
      .deviceNotInProfile(
        release: "1.2.0 (88)", device: "Karlo's iPhone", profile: "MyApp AdHoc", deviceCount: 12),
      .firebaseAccessDenied("requires a quota project\nrun gcloud"),
      .invalidFirebaseAppID("nope"),
    ]
    for error in errors {
      let lines = SimulatorTUI.entryLines(error.localizedDescription)
      XCTAssertFalse(lines.isEmpty, "\(error) produced nothing")
      for line in lines {
        XCTAssertFalse(line.contains(where: \.isNewline), "newline survived in: \(line)")
        XCTAssertFalse(line.contains("\t"), "tab survived in: \(line)")
      }
    }
  }

  /// The renderer is the backstop: even if something multi-line reaches it, the
  /// frame must stay intact.
  func testTheRendererNeverEmitsAStrayNewlineFromOutput() {
    var state = TUIState(devices: [
      Device(name: "iPhone 16", udid: "S1", state: "Booted", isAvailable: true)
    ])
    state.output = [SimctlBuddyError.noFirebaseCredential.localizedDescription]

    let screen = TUIRenderer().render(state: state, columns: 120, rows: 30)
    // Every line the renderer draws is cursor-positioned, so each newline in the
    // output must be preceded by a reposition escape rather than appearing raw.
    for line in screen.components(separatedBy: "\n") where line.contains("credential") {
      XCTAssertTrue(line.contains("\u{001B}["), "an output line was drawn without positioning")
    }
    XCTAssertTrue(screen.contains("gcloud"))
  }
}

final class FirebaseGuidanceRenderTests: XCTestCase {
  private var device: Device {
    Device(name: "iPhone 16", udid: "S1", state: "Booted", isAvailable: true)
  }

  private func screen(output: [String]) -> String {
    var state = TUIState(devices: [device])
    state.output = output
    return TUIRenderer().render(state: state, columns: 120, rows: 32)
  }

  /// The frame is a fixed number of rows. A newline escaping into it would add
  /// rows and push everything below out of place, which is what tore the header
  /// off the top of the screen.
  func testOutputContentCannotChangeTheFrameHeight() {
    let baseline = screen(output: ["ok"]).components(separatedBy: "\n").count
    let multiline = screen(output: ["line one\nline two\nline three"])
      .components(separatedBy: "\n").count
    XCTAssertEqual(multiline, baseline)
  }

  func testTheRawErrorCannotChangeTheFrameHeightEither() {
    let baseline = screen(output: ["ok"]).components(separatedBy: "\n").count
    let raw = screen(output: [SimctlBuddyError.noFirebaseCredential.localizedDescription])
      .components(separatedBy: "\n").count
    XCTAssertEqual(raw, baseline)
  }

  /// The guide has to actually be readable once it is on screen.
  func testTheSetupGuideIsLegible() {
    let rendered = screen(output: [
      "\u{2717} Not signed in to Firebase \u{2014} 3 steps to set it up",
      "  1. Sign in with ONE of these, in a normal terminal:",
      "       gcloud auth login",
      "  2. Save an app: the \u{201C}Save Firebase app ID\u{201D} action below.",
      "  3. Select a connected device, then press f to pick a build.",
    ])
    XCTAssertTrue(rendered.contains("gcloud auth login"))
    XCTAssertTrue(rendered.contains("press f"))
    XCTAssertTrue(rendered.contains("Save Firebase app ID"))
  }
}

/// Signing a service account assertion runs through Security.framework and a
/// hand-rolled DER unwrap, so it is exercised against a real RSA key rather
/// than only against the parsing helpers.
///
/// The key below was generated for this test alone and grants access to nothing.
final class ServiceAccountSigningTests: XCTestCase {
  private let testPEM = """
      -----BEGIN PRIVATE KEY-----
      MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDRE1oLKzZItoyb
      +xu2i+GIo05rLqC15Yvhxoau1fyqozytNvOdtpzBgW310P+Vw0sKLcGmueRz90Wb
      JlZrcv/vL41Eei73wUs8HUtgglePv0swKpjeWY4C1LdeT02iH23J9J/dhWeKOb6c
      1yKqt/GfsVPqVe3dJ9MAxktBqXPFSfbWO1O35Dcuq4pBF84PPemVk17WgZoyMxoM
      XrQyjJa9qXqZdyVWIzeR9FApFTypnUXAW7chA6lUPXIfqS+kyo405WDaiTHzrWXH
      +uiJrDmsjnFykRKL+liP6sXo2He1D1DM/36bTf0w4ArR8NfkhllB39coGky+Jsbu
      CVr9PTxTAgMBAAECggEABhNiY/2y+6T2bBf9g64H9VENl9bIi9CqYnrC8jS8vXa1
      7jCxHq2uW38341NaAg+lUBvpSz+OsIIIj0wrab7zSg+fMtS8Ja4D0jDlvl27Tq2X
      8UPjol6G3nUxCPgUAPiZ16sYtDbKvf0UmXk1BDIJPwNHtYEewvUD0Dty92sFtr90
      hP+7UqLgRcfpaGxrxZSNGe37ksOSNAb57iYXYZBn9Fs1ww9S8DwTZ1zQbPlySHrb
      Fq3Bvrqz70rWB9Ybp4CuT1T2ogXKyqbH8ftkpNDsj54mMvP2IuQGlxGXMht5UQ7I
      JxMr7ouQvVtsYUfs+/7F4uXUMqXF6xa13h4D+OQiWQKBgQD5ygd3B3FqATRUzfCs
      8ugyvuPidDwwhxfoFO9eV94RVdWMjYKtJTEHQA+oZVn1Ii1fsxMkGrody1G2blPl
      nmXZFMj5O+BpljhiudM/WjvUCfTSuhjf3O0D7uxDn7TEbCSI+pHPlrQNJtGuDHGi
      iSDOKd+HSGgW+qG5uwyZ2sClqwKBgQDWRiueidf2sRqRrtuPVWtUyG0D+p12FsBV
      gN/5Wnmf/DQoWRmAhGsDKd/YQDhjbkg8aT8bqa4RapK0aTLyTVJAC5NNeiy9SHpg
      LAR+WEsLkbPJ/VZhNmPDpVam41yjBBTkeO3rAbYxx8QQdiYe2kDLueEdM4KMwEbB
      JDeM7PlL+QKBgDimL+E3x+nhkgu1lOK0SCLSFf6Sm9/pk2tn7A16YfuOetrgcQVx
      jNf3GFX5flhQwveUNkAW66S8KrDz/oTx0mlUBGw5vyBTGECToiwY+76P730nBWMn
      yHz+34hKnQV6/SIvqYfpxrXA2wbc/Zx9+vmml3In4qtrdegYWrg92zj3AoGBAI4g
      MSKRb+wzgNoMz5l9IRo1bwnqm7MOWDjeqLEur+nMUZRJtT6nloucpNs9jal2Jvfb
      H37rx4fJ1tFPzfkmDF5qzyPe2/oZLwLHb5uWWQCtfkGGhlsoxnepHZbIzFNci7cX
      90ef9QeD56q7k4F3Zu86tfS2i+tsRgIqUaZqMNmRAoGATJM6DFUTe/nSTtFwwgqr
      l5yZzykebBTE1gCzsxHvMZDpNgZSPnM4pJ+VJ4d0k2FKV/XS+8NjrkTamUbzMSmA
      4L19k0cS4UAfOKklB2r18PvR0j7lOs9bRrdPXOPcXLQnvhV/teUds1OrKFfRTzGo
      Yh6fJcJEtSMEiOI0lT200fA=
      -----END PRIVATE KEY-----
    """

  private func key() throws -> ServiceAccountKey {
    // Built with JSONSerialization so the PEM's newlines are escaped correctly,
    // exactly as they are in a real key file.
    let json = try JSONSerialization.data(withJSONObject: [
      "client_email": "simbuddy@example.iam.gserviceaccount.com",
      "private_key": testPEM,
      "token_uri": "https://oauth2.googleapis.com/token",
    ])
    return try JSONDecoder().decode(ServiceAccountKey.self, from: json)
  }

  private func decodeSegment(_ segment: String) throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: try base64URLDecode(segment)) as? [String: Any])
  }

  private func base64URLDecode(_ value: String) throws -> Data {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 { base64 += "=" }
    return try XCTUnwrap(Data(base64Encoded: base64))
  }

  func testARealKeyProducesAThreePartJWT() throws {
    let assertion = try key().signedAssertion(scope: FirebaseClient.scope)
    XCTAssertEqual(assertion.split(separator: ".").count, 3)
  }

  func testTheHeaderAndClaimsSayWhatGoogleExpects() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let assertion = try key().signedAssertion(scope: FirebaseClient.scope, now: now)
    let parts = assertion.split(separator: ".").map(String.init)

    let header = try decodeSegment(parts[0])
    XCTAssertEqual(header["alg"] as? String, "RS256")
    XCTAssertEqual(header["typ"] as? String, "JWT")

    let claims = try decodeSegment(parts[1])
    XCTAssertEqual(claims["iss"] as? String, "simbuddy@example.iam.gserviceaccount.com")
    XCTAssertEqual(claims["scope"] as? String, FirebaseClient.scope)
    XCTAssertEqual(claims["aud"] as? String, "https://oauth2.googleapis.com/token")
    XCTAssertEqual(claims["iat"] as? Int, 1_700_000_000)
    // Google rejects an assertion valid for longer than an hour.
    XCTAssertEqual(claims["exp"] as? Int, 1_700_000_000 + 3600)
  }

  /// The point of the whole exercise: the signature has to actually verify.
  func testTheSignatureVerifiesAgainstThePublicKey() throws {
    let assertion = try key().signedAssertion(scope: FirebaseClient.scope)
    let parts = assertion.split(separator: ".").map(String.init)
    let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
    let signature = try base64URLDecode(parts[2])

    let der = try ServiceAccountKey.pkcs1(from: testPEM)
    let privateKey = try XCTUnwrap(
      SecKeyCreateWithData(
        der as CFData,
        [
          kSecAttrKeyType: kSecAttrKeyTypeRSA,
          kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ] as CFDictionary,
        nil))
    let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(privateKey))

    XCTAssertTrue(
      SecKeyVerifySignature(
        publicKey, .rsaSignatureMessagePKCS1v15SHA256,
        signingInput as CFData, signature as CFData, nil),
      "the signed assertion did not verify")
  }
}

final class OAuthErrorTests: XCTestCase {
  /// The token endpoint answers with a flat shape, unlike the rest of Google's
  /// APIs. Reading it keeps raw JSON off the screen.
  func testTheTokenEndpointsErrorShapeIsRead() {
    let body = Data(#"{"error":"invalid_grant","error_description":"Invalid grant: account not found"}"#.utf8)
    let text = FirebaseCredentials.errorText(HTTPResponse(statusCode: 400, body: body))
    XCTAssertEqual(text, "Invalid grant: account not found")
  }

  func testTheErrorCodeIsUsedWhenThereIsNoDescription() {
    let body = Data(#"{"error":"invalid_client"}"#.utf8)
    XCTAssertEqual(
      FirebaseCredentials.errorText(HTTPResponse(statusCode: 401, body: body)), "invalid_client")
  }

  func testTheAPIEnvelopeStillWins() {
    let body = Data(#"{"error":{"message":"Permission denied","status":"PERMISSION_DENIED"}}"#.utf8)
    XCTAssertEqual(
      FirebaseCredentials.errorText(HTTPResponse(statusCode: 403, body: body)), "Permission denied")
  }

  func testAnEmptyBodyFallsBackToTheStatusCode() {
    XCTAssertEqual(
      FirebaseCredentials.errorText(HTTPResponse(statusCode: 500, body: Data())), "HTTP 500")
  }
}

final class CredentialDiscoveryTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory
      .appendingPathComponent("creds-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func credentials(environment: [String: String] = [:]) -> FirebaseCredentials {
    FirebaseCredentials(
      environment: environment,
      settingsStore: SettingsStore(fileURL: home.appendingPathComponent("settings.json"))
    )
  }

  func testARawTokenInTheEnvironmentIsFoundFirst() throws {
    let token = try credentials(environment: ["SIMBUDDY_FIREBASE_TOKEN": "ya29.test"]).token()
    XCTAssertEqual(token.accessToken, "ya29.test")
    XCTAssertEqual(token.source, .environment)
  }

  func testBlankEnvironmentValuesAreIgnored() {
    let sources = credentials(environment: ["SIMBUDDY_FIREBASE_TOKEN": "   "]).availableSources()
    XCTAssertFalse(sources.contains { $0.contains("SIMBUDDY_FIREBASE_TOKEN") })
  }

  func testAMissingServiceAccountFileIsReportedClearly() {
    let path = home.appendingPathComponent("nope.json").path
    XCTAssertThrowsError(
      try credentials(environment: ["GOOGLE_APPLICATION_CREDENTIALS": path]).token()
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("No file at"))
    }
  }

  func testSomethingThatIsNotAKeyFileIsReportedClearly() throws {
    let path = home.appendingPathComponent("junk.json")
    try Data("not a key".utf8).write(to: path)
    XCTAssertThrowsError(
      try credentials(environment: ["GOOGLE_APPLICATION_CREDENTIALS": path.path]).token()
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("not a Google service account key"))
    }
  }

  /// A bare user credential has to name a project for quota. A service account
  /// bills its own, and the Firebase CLI's OAuth client carries one — naming a
  /// project for those only invites a 403 on projects shared with you.
  func testOnlyBareUserCredentialsNameAQuotaProject() {
    for source in [FirebaseToken.Source.serviceAccount(email: "a@b"), .firebaseCLI] {
      XCTAssertFalse(FirebaseToken(accessToken: "t", source: source).needsQuotaProject)
    }
    for source in [FirebaseToken.Source.gcloud, .environment] {
      XCTAssertTrue(FirebaseToken(accessToken: "t", source: source).needsQuotaProject)
    }
  }
}

/// CI writes a whole commit log into release notes, opening with a heading that
/// repeats the version. These cases are taken from real App Distribution data.
final class ReleaseNotesSummaryTests: XCTestCase {
  private func release(notes: String?) -> FirebaseRelease {
    FirebaseRelease(
      name: "projects/1/apps/1:1:ios:a/releases/r1",
      displayVersion: "2.14.0", buildVersion: "161632", releaseNotes: notes)
  }

  func testTheVersionHeadingIsSkipped() {
    let notes = """
      # Version: 2.14.0.161632-ccaef09-feature/SPARPAPP-10891
      - Merge pull request 15138 from feature/SPARPAPP-10891 into store - (ccaef0911) [Someone]
      """
    XCTAssertEqual(
      release(notes: notes).summaryLine,
      "Merge pull request 15138 from feature/SPARPAPP-10891 into store")
  }

  func testTheTrailingShaAndAuthorAreDropped() {
    let notes = "- Run the pipeline on feature/login - (84a5027b2) [Karlo]"
    XCTAssertEqual(release(notes: notes).summaryLine, "Run the pipeline on feature/login")
  }

  /// A ticket reference starts with '#' mid-line but is not a heading.
  func testATicketReferenceIsNotMistakenForAHeading() {
    let notes = "- #SPARPAPP-10464: Continuous Improvement - (4707951cc) [Someone]"
    XCTAssertEqual(
      release(notes: notes).summaryLine, "#SPARPAPP-10464: Continuous Improvement")
  }

  func testNotesThatAreOnlyHeadingsProduceNothing() {
    XCTAssertNil(release(notes: "# Version: 1.2.3\n\n#  \n").summaryLine)
  }

  func testAbsentNotesProduceNothing() {
    XCTAssertNil(release(notes: nil).summaryLine)
    XCTAssertNil(release(notes: "").summaryLine)
  }

  func testAPlainSingleLineIsUsedAsIs() {
    XCTAssertEqual(release(notes: "Fixed the login crash").summaryLine, "Fixed the login crash")
  }
}

/// Access is granted per project, so a walk across projects normally comes back
/// partly refused. That has to read as a partial answer, not a failure.
final class ProjectWalkTests: XCTestCase {
  private func app(_ name: String, _ id: String) -> FirebaseApp {
    FirebaseApp(appID: id, displayName: name)
  }

  func testAReadableProjectReportsNoProblem() {
    let listing = FirebaseProjectApps(
      projectID: "p1", projectName: "P1", apps: [app("A", "1:1:ios:a")])
    XCTAssertTrue(listing.isReadable)
    XCTAssertEqual(listing.apps.count, 1)
  }

  func testARefusedProjectIsMarkedAndCarriesNoApps() {
    let listing = FirebaseProjectApps(
      projectID: "p2", projectName: "P2", apps: [], problem: "not allowed")
    XCTAssertFalse(listing.isReadable)
    XCTAssertTrue(listing.apps.isEmpty)
  }

  /// An empty but readable project is a different thing from a refused one, and
  /// the two must not be reported the same way.
  func testAnEmptyProjectIsNotTreatedAsRefused() {
    let listing = FirebaseProjectApps(projectID: "p3", projectName: "P3", apps: [])
    XCTAssertTrue(listing.isReadable)
    XCTAssertTrue(listing.apps.isEmpty)
  }
}

/// Naming a quota project is what made projects shared with this account look
/// unreadable: `x-goog-user-project` needs `serviceusage.services.use` on that
/// project, and a tester on someone else's project does not have it — while the
/// same request without the header is answered.
final class QuotaProjectRetryTests: XCTestCase {
  /// Answers the serviceusage refusal to any request naming a quota project,
  /// and the app list to any request that does not.
  private final class QuotaRefusingHTTP: HTTPRequesting, @unchecked Sendable {
    private(set) var requests: [HTTPRequest] = []

    func perform(_ request: HTTPRequest) throws -> HTTPResponse {
      requests.append(request)
      guard request.headers["x-goog-user-project"] == nil else {
        return HTTPResponse(
          statusCode: 403,
          body: Data(
            #"{"error":{"message":"Caller does not have required permission to use project p1."}}"#
              .utf8))
      }
      return HTTPResponse(
        statusCode: 200,
        body: Data(#"{"apps":[{"appId":"1:1:ios:a","displayName":"A","bundleId":"com.a"}]}"#.utf8))
    }

    func download(_ request: HTTPRequest, to destination: URL) throws {
      throw SimctlBuddyError.invalidResponse("not used")
    }
  }

  private func client(_ http: QuotaRefusingHTTP) -> FirebaseClient {
    FirebaseClient(
      http: http,
      credentials: FirebaseCredentials(
        http: http,
        environment: [FirebaseCredentials.tokenEnvironmentKey: "t"],
        settingsStore: SettingsStore(
          fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-\(UUID().uuidString).json"))))
  }

  func testAProjectRefusedOnlyOverQuotaIsReadOnTheRetry() throws {
    let http = QuotaRefusingHTTP()
    let apps = try client(http).iosApps(projectID: "p1")

    XCTAssertEqual(apps.map(\.appID), ["1:1:ios:a"])
    XCTAssertEqual(http.requests.count, 2, "the header should have been dropped and retried")
    XCTAssertNil(http.requests.last?.headers["x-goog-user-project"])
  }

  /// Only that one refusal is worth a second call. A missing role is a real no.
  func testAnOrdinaryForbiddenIsNotRetried() {
    let response = HTTPResponse(
      statusCode: 403,
      body: Data(#"{"error":{"message":"The caller does not have permission"}}"#.utf8))
    XCTAssertFalse(FirebaseClient.isQuotaProjectRefusal(response))
  }
}

final class AppBrowserPickerTests: XCTestCase {
  /// Saving an app is not device work, so the browser stays reachable even on a
  /// simulator that could never install a build.
  func testTheSaveRowIsAvailableOnEveryKind() {
    for kind in DeviceKind.allCases {
      let state = TUIState(devices: [
        Device(name: "d", udid: "u", state: "Booted", isAvailable: true, kind: kind)
      ])
      XCTAssertTrue(
        state.actions.contains { $0.id == .saveFirebaseApp },
        "the save row vanished on \(kind)")
    }
  }

  func testTheBrowserPurposeIsDistinctFromTheInstallPurpose() {
    XCTAssertNotEqual(TUIPickerPurpose.firebaseAppToSave, .firebaseApp)
  }
}
