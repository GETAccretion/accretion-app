import XCTest
@testable import AccretionCore

final class InstallCertificatePlanTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func days(_ count: Double) -> Date { now.addingTimeInterval(count * 86400) }

	private func fetch(method: Int = 0, _ expiries: [Date], lastTry: Date? = nil) -> Bool {
		InstallCertificatePlan.shouldFetch(method: method, expiries: expiries, lastTry: lastTry, now: now)
	}

	func testOnlyFullyLocalFetches() {
		XCTAssertTrue(fetch(method: 0, [days(-1)]))
		XCTAssertFalse(fetch(method: 1, [days(-1)]), "Semi Local doesn't use the certificate")
		XCTAssertFalse(fetch(method: 2, [days(-1)]), "Offline makes its own")
	}

	func testFetchesWhenTheBestCertificateRunsOutSoon() {
		XCTAssertFalse(fetch([days(30)]))
		XCTAssertTrue(fetch([days(6)]), "less than the margin left")
		XCTAssertTrue(fetch([days(-10), days(-1)]), "both ran out")
		XCTAssertFalse(fetch([days(-10), days(30)]), "one copy that still lasts is enough")
		XCTAssertTrue(fetch([]), "nothing readable on the device")
	}

	func testWaitsBetweenTries() {
		XCTAssertFalse(fetch([days(-1)], lastTry: now.addingTimeInterval(-3600)))
		XCTAssertTrue(fetch([days(-1)], lastTry: now.addingTimeInterval(-13 * 3600)))
		XCTAssertTrue(fetch([days(-1)], lastTry: now.addingTimeInterval(3600)), "a clock set back doesn't block it")
	}
}
