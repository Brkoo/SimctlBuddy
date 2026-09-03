import XCTest

@testable import SimctlBuddyCore

final class LinkTemplateTests: XCTestCase {
  func testAFinishedURLIsNotATemplate() {
    let template = LinkTemplate.parse("sparatappqa://navigate/bills")
    XCTAssertFalse(template.isTemplate)
    XCTAssertFalse(template.requiresScheme)
    XCTAssertTrue(template.parameters.isEmpty)
    XCTAssertEqual(try template.render(), "sparatappqa://navigate/bills")
  }

  func testSchemeIsFilledInFromTheApp() throws {
    let template = LinkTemplate.parse("$scheme://navigate/bills")
    XCTAssertTrue(template.requiresScheme)
    XCTAssertEqual(
      try template.render(scheme: "sparsiappqa"), "sparsiappqa://navigate/bills")
  }

  func testRenderingWithoutASchemeIsRefused() {
    let template = LinkTemplate.parse("$scheme://navigate/bills")
    XCTAssertThrowsError(try template.render()) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .missingLinkScheme)
    }
  }

  func testNamedParameterWithADefault() throws {
    let template = LinkTemplate.parse("$scheme://automation?staging-slot=$slot=staging5")
    XCTAssertEqual(template.parameters.map(\.name), ["slot"])
    XCTAssertEqual(template.parameters[0].defaultValue, "staging5")

    XCTAssertEqual(
      try template.render(scheme: "sparatappqa"),
      "sparatappqa://automation?staging-slot=staging5")
    XCTAssertEqual(
      try template.render(scheme: "sparatappqa", values: ["slot": "staging7"]),
      "sparatappqa://automation?staging-slot=staging7")
  }

  func testADefaultEndsAtAQueryDelimiter() throws {
    let template = LinkTemplate.parse("myapp://x?a=$one=first&b=$two=second")
    XCTAssertEqual(template.parameters.map(\.name), ["one", "two"])
    XCTAssertEqual(template.parameters.map(\.defaultValue), ["first", "second"])
    XCTAssertEqual(try template.render(), "myapp://x?a=first&b=second")
  }

  func testBracketsAllowADefaultContainingDelimiters() throws {
    let template = LinkTemplate.parse("myapp://x?q=${query=a&b}")
    XCTAssertEqual(template.parameters[0].defaultValue, "a&b")
    XCTAssertEqual(try template.render(), "myapp://x?q=a&b")
  }

  func testPositionalParameters() throws {
    let template = LinkTemplate.parse("$scheme://profile/$0?ref=$1")
    XCTAssertEqual(template.parameters.map(\.name), ["0", "1"])
    XCTAssertTrue(template.parameters.allSatisfy(\.isPositional))
    XCTAssertEqual(template.parameters[0].label, "Parameter 0")
    XCTAssertEqual(
      try template.render(scheme: "myapp", values: ["0": "42", "1": "terminal"]),
      "myapp://profile/42?ref=terminal")
  }

  func testAMissingValueNamesTheParameter() {
    let template = LinkTemplate.parse("myapp://profile/$id")
    XCTAssertThrowsError(try template.render()) { error in
      XCTAssertEqual(error as? SimctlBuddyError, .missingLinkParameter("id"))
    }
    XCTAssertEqual(template.unresolvedParameters(given: [:]).map(\.name), ["id"])
    XCTAssertTrue(template.unresolvedParameters(given: ["id": "7"]).isEmpty)
  }

  func testAParameterWithADefaultIsNeverUnresolved() {
    let template = LinkTemplate.parse("myapp://x?a=$slot=staging5")
    XCTAssertTrue(template.unresolvedParameters(given: [:]).isEmpty)
  }

  func testTheSameParameterTwiceIsAskedForOnce() throws {
    let template = LinkTemplate.parse("myapp://$id/detail/$id")
    XCTAssertEqual(template.parameters.map(\.name), ["id"])
    XCTAssertEqual(try template.render(values: ["id": "7"]), "myapp://7/detail/7")
  }

  func testADefaultGivenInOnlyOnePlaceStillApplies() throws {
    let template = LinkTemplate.parse("myapp://$id/detail/$id=9")
    XCTAssertEqual(template.parameters[0].defaultValue, "9")
    XCTAssertEqual(try template.render(), "myapp://9/detail/9")
  }

  func testDoubleDollarIsALiteralDollar() throws {
    let template = LinkTemplate.parse("myapp://pay?amount=$$5")
    XCTAssertTrue(template.parameters.isEmpty)
    XCTAssertEqual(try template.render(), "myapp://pay?amount=$5")
  }

  func testALoneDollarIsLeftAlone() throws {
    XCTAssertEqual(try LinkTemplate.parse("myapp://x?a=$").render(), "myapp://x?a=$")
    XCTAssertEqual(try LinkTemplate.parse("myapp://x?a=$ b").render(), "myapp://x?a=$ b")
  }

  func testAnUnterminatedBraceIsTreatedAsText() throws {
    XCTAssertEqual(try LinkTemplate.parse("myapp://x?q=${oops").render(), "myapp://x?q=${oops")
  }

  func testValidationAcceptsTemplatesAndRejectsRubbish() {
    XCTAssertNoThrow(try LinkTemplate.parse("$scheme://navigate/bills").validate())
    XCTAssertNoThrow(try LinkTemplate.parse("myapp://profile/$id").validate())
    XCTAssertNoThrow(
      try LinkTemplate.parse("$scheme://automation?staging-slot=$slot=staging5").validate())
    // A parameter may supply the scheme itself, which is a real use, not a typo.
    XCTAssertNoThrow(try LinkTemplate.parse("$market://x").validate())
    // No scheme at all is still not a deep link.
    XCTAssertThrowsError(try LinkTemplate.parse("navigate/bills").validate())
    XCTAssertThrowsError(try LinkTemplate.parse("").validate())
  }

  func testSchemeValidation() {
    XCTAssertTrue(LinkTemplate.isValidScheme("sparatappqa"))
    XCTAssertTrue(LinkTemplate.isValidScheme("my-app.v2"))
    XCTAssertFalse(LinkTemplate.isValidScheme("2fast"))
    XCTAssertFalse(LinkTemplate.isValidScheme("has space"))
    XCTAssertFalse(LinkTemplate.isValidScheme(""))
  }

  /// The case that prompted all this: two markets, one definition.
  func testOneDefinitionCoversEveryMarket() throws {
    let template = LinkTemplate.parse("$scheme://automation?staging-slot=$slot=staging5")
    XCTAssertEqual(
      try template.render(scheme: "sparatappqa", values: ["slot": "staging5"]),
      "sparatappqa://automation?staging-slot=staging5")
    XCTAssertEqual(
      try template.render(scheme: "sparsiappqa", values: ["slot": "staging"]),
      "sparsiappqa://automation?staging-slot=staging")
  }
}
