import XCTest
@testable import AccretionCore

final class AppIDFitTests: XCTestCase {
	func testKindFromAppID() {
		XCTAssertEqual(AppIDKind(appID: "*"), .wildcard(prefix: ""))
		XCTAssertEqual(AppIDKind(appID: "com.example.*"), .wildcard(prefix: "com.example."))
		XCTAssertEqual(AppIDKind(appID: "app.salmon.dusk"), .explicit("app.salmon.dusk"))
		XCTAssertNil(AppIDKind(appID: ""))
		XCTAssertNil(AppIDKind(appID: nil))
	}

	func testExplicitKeepsTheAppsOwnIDByDefault() {
		let kind = AppIDKind.explicit("app.salmon.dusk")
		XCTAssertEqual(AppIDFit.bundleID("com.radio.app", for: kind, keepOwnID: true), "com.radio.app")
		XCTAssertEqual(AppIDFit.bundleID("com.radio.app", for: kind, keepOwnID: false), "app.salmon.dusk", "the old rename, now an option")
	}

	func testWildcardsIgnoreTheSetting() {
		for keep in [true, false] {
			XCTAssertEqual(AppIDFit.bundleID("com.radio.app", for: .wildcard(prefix: ""), keepOwnID: keep), "com.radio.app")
			XCTAssertEqual(AppIDFit.bundleID("com.radio.app", for: .wildcard(prefix: "com.example."), keepOwnID: keep), "com.example.com.radio.app")
			XCTAssertEqual(AppIDFit.bundleID("com.example.app", for: .wildcard(prefix: "com.example."), keepOwnID: keep), "com.example.app")
			XCTAssertEqual(AppIDFit.bundleID("com.radio.app", for: nil, keepOwnID: keep), "com.radio.app")
		}
	}
}
