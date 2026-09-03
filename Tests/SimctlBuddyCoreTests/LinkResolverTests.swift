import Foundation
import XCTest

@testable import SimctlBuddyCore

final class LinkResolverTests: XCTestCase {
  private let at = SavedApp(
    name: "SparAT", bundleIdentifier: "at.spar.mobile.spar-app.ent.qa", scheme: "sparatappqa")
  private let si = SavedApp(
    name: "SparSI", bundleIdentifier: "si.spar.plus.ent.qa", scheme: "sparsiappqa")
  private let noScheme = SavedApp(
    name: "iDart", bundleIdentifier: "com.karlohorvat.iDart")

  private var apps: [SavedApp] { [at, si, noScheme] }

  func testOnlyAppsWithASchemeCanOpenASchemeLink() {
    let link = SavedLink(name: "bills", url: "$scheme://navigate/bills")
    XCTAssertEqual(
      LinkResolver.candidates(for: link, apps: apps).map(\.name), ["SparAT", "SparSI"])
  }

  func testAPlainLinkOffersEveryApp() {
    let link = SavedLink(name: "bills", url: "myapp://navigate/bills")
    XCTAssertEqual(LinkResolver.candidates(for: link, apps: apps).count, 3)
  }

  func testARestrictedLinkOnlyOffersItsOwnApps() {
    let link = SavedLink(
      name: "purchase",
      url: "$scheme://navigate/purchasepopup",
      apps: ["at.spar.mobile.spar-app.ent.qa"]
    )
    XCTAssertEqual(LinkResolver.candidates(for: link, apps: apps).map(\.name), ["SparAT"])
    XCTAssertTrue(link.appliesTo(bundleIdentifier: "AT.Spar.Mobile.Spar-App.ENT.QA"))
    XCTAssertFalse(link.appliesTo(bundleIdentifier: "si.spar.plus.ent.qa"))
    XCTAssertTrue(link.isRestricted)
  }

  func testAnUnrestrictedLinkAppliesToAnything() {
    let link = SavedLink(name: "bills", url: "$scheme://navigate/bills")
    XCTAssertTrue(link.appliesTo(bundleIdentifier: "anything.at.all"))
    XCTAssertFalse(link.isRestricted)
    // An empty list is stored as no restriction rather than "no app may open it".
    XCTAssertNil(SavedLink(name: "x", url: "myapp://x", apps: []).apps)
  }

  func testInstalledAppsComeFirst() {
    let link = SavedLink(name: "bills", url: "$scheme://navigate/bills")
    let ordered = LinkResolver.candidates(
      for: link, apps: apps, installed: ["si.spar.plus.ent.qa"])
    XCTAssertEqual(ordered.map(\.name), ["SparSI", "SparAT"])
  }

  func testASingleCandidateNeedsNoQuestion() {
    XCTAssertEqual(LinkResolver.automaticChoice(from: [at], remembered: nil)?.name, "SparAT")
  }

  func testSeveralCandidatesAreAmbiguousUnlessOneIsRemembered() {
    XCTAssertNil(LinkResolver.automaticChoice(from: [at, si], remembered: nil))
    XCTAssertEqual(
      LinkResolver.automaticChoice(from: [at, si], remembered: si.bundleIdentifier)?.name,
      "SparSI")
  }

  func testARememberedAppThatNoLongerAppliesIsIgnored() {
    // The link was later restricted to AT, so a remembered SI must not win.
    XCTAssertNil(LinkResolver.automaticChoice(from: [at, si], remembered: "gone.example.app"))
    XCTAssertEqual(
      LinkResolver.automaticChoice(from: [at], remembered: "si.spar.plus.ent.qa")?.name,
      "SparAT")
  }

  func testFindingAnAppByNameOrIdentifier() throws {
    XCTAssertEqual(try LinkResolver.app(matching: "SparAT", in: apps).name, "SparAT")
    XCTAssertEqual(try LinkResolver.app(matching: "sparat", in: apps).name, "SparAT")
    XCTAssertEqual(
      try LinkResolver.app(matching: "si.spar.plus.ent.qa", in: apps).name, "SparSI")
    XCTAssertEqual(try LinkResolver.app(matching: "iDart", in: apps).name, "iDart")
  }

  func testAnAmbiguousOrUnknownAppSelectorIsReported() {
    XCTAssertThrowsError(try LinkResolver.app(matching: "Spar", in: apps))
    XCTAssertThrowsError(try LinkResolver.app(matching: "nope", in: apps)) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .appNotFound("nope"))
    }
  }

  func testParsingAssignments() throws {
    XCTAssertEqual(
      try LinkResolver.parseAssignments(["slot=staging5", "0=42"]),
      ["slot": "staging5", "0": "42"])
    // A value may contain "=" itself.
    XCTAssertEqual(try LinkResolver.parseAssignments(["q=a=b"]), ["q": "a=b"])
    // An empty value is a legitimate choice.
    XCTAssertEqual(try LinkResolver.parseAssignments(["slot="]), ["slot": ""])
  }

  func testRubbishAssignmentsAreRejected() {
    XCTAssertThrowsError(try LinkResolver.parseAssignments(["slot"])) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .invalidAssignment("slot"))
    }
    XCTAssertThrowsError(try LinkResolver.parseAssignments(["=value"]))
  }
}
