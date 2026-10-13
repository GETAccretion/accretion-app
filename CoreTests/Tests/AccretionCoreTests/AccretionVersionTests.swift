import XCTest
@testable import AccretionCore

final class AccretionVersionTests: XCTestCase {
	func testNumbersIgnoreEverythingElse() {
		XCTAssertEqual(AccretionVersion.numbers("4.0.0-mod1.10.0"), [4, 0, 0, 1, 10, 0])
		XCTAssertEqual(AccretionVersion.numbers("v2.0b (45)"), [2, 0, 45])
		XCTAssertEqual(AccretionVersion.numbers("beta"), [])
	}

	func testNumericOrder() {
		XCTAssertTrue(AccretionVersion.isNewer("1.0.10", than: "1.0.9"))
		XCTAssertFalse(AccretionVersion.isNewer("1.0.9", than: "1.0.10"))
		XCTAssertFalse(AccretionVersion.isNewer("1.0", than: "1.0.0"), "missing numbers count as 0")
		XCTAssertFalse(AccretionVersion.isNewer("1.0.0", than: "1.0"))
		XCTAssertFalse(AccretionVersion.isNewer("2.0b", than: "2.0"), "letters are ignored")
	}

	func testBetasSitBetweenReleases() {
		XCTAssertTrue(AccretionVersion.isNewer("1.0.25.1", than: "1.0.25"))
		XCTAssertTrue(AccretionVersion.isNewer("1.0.25.2", than: "1.0.25.1"))
		XCTAssertTrue(AccretionVersion.isNewer("1.0.26", than: "1.0.25.9"), "the next release replaces every beta")
		XCTAssertTrue(AccretionVersion.isBeta("1.0.25.1"))
		XCTAssertFalse(AccretionVersion.isBeta("1.0.25"))
		XCTAssertFalse(AccretionVersion.isBeta("4.0.0-mod1.0.0"))
	}

	func testModVersions() {
		let order = ["4.0.0", "4.0.0-mod1.0.0", "4.0.0-mod1.1.0", "4.0.0-mod1.10.0", "4.0.0-mod2.0.0", "4.1.0-mod1.0.0"]
		for (older, newer) in zip(order, order.dropFirst()) {
			XCTAssertTrue(AccretionVersion.isNewer(newer, than: older), "\(newer) should be newer than \(older)")
			XCTAssertFalse(AccretionVersion.isNewer(older, than: newer))
		}
	}
}
