import XCTest

@testable import SimctlBuddyCore

final class DeepLinkTests: XCTestCase {
  func testAcceptsCustomScheme() {
    XCTAssertTrue(SimctlClient.isValidDeepLink("myapp://profile/42?source=test"))
  }

  func testAcceptsUniversalLink() {
    XCTAssertTrue(SimctlClient.isValidDeepLink("https://example.com/profile/42"))
  }

  func testRejectsMissingScheme() {
    XCTAssertFalse(SimctlClient.isValidDeepLink("example.com/profile/42"))
  }

  func testRejectsInvalidScheme() {
    XCTAssertFalse(SimctlClient.isValidDeepLink("1app://profile"))
  }

  func testCoordinateValidation() throws {
    let client = SimctlClient()
    XCTAssertNoThrow(try client.validateCoordinate(latitude: 46.0569, longitude: 14.5058))
    XCTAssertThrowsError(try client.validateCoordinate(latitude: 91, longitude: 14))
    XCTAssertThrowsError(try client.validateCoordinate(latitude: 46, longitude: -181))
  }
}
