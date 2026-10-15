import Foundation
import XCTest
@testable import AccretionCore

final class AccretionSourcesTests: XCTestCase {
	private let account = "fixture.supabase.co"

	private func trusted(_ link: String) -> Bool {
		AccretionSources.trustsForCrossSourceUpdates(URL(string: link)!, accountHost: account)
	}

	func testAccretionsOwnSourcesMayUpdateAnyApp() {
		XCTAssertTrue(trusted("https://getaccretion.app/source.json"))
		XCTAssertTrue(trusted("https://getaccretion.app/curated.json"))
		XCTAssertTrue(trusted("https://raw.githubusercontent.com/AccretionMods/mods/main/mods.json"))
		XCTAssertTrue(trusted("https://raw.githubusercontent.com/GETAccretion/accretion-app/main/app-repo.json"))
		XCTAssertTrue(trusted("https://fixture.supabase.co/functions/v1/source?key=fictional"))
		XCTAssertTrue(trusted("HTTPS://GETACCRETION.APP/source.json"))
	}

	func testOtherSourcesMayOnlyUpdateTheirOwnApps() {
		XCTAssertFalse(trusted("https://example.invalid/source.json"))
		XCTAssertFalse(trusted("https://raw.githubusercontent.com/someone/else/main/apps.json"))
		XCTAssertFalse(trusted("https://raw.githubusercontent.com/AccretionModsX/mods/main/mods.json"))
		XCTAssertFalse(trusted("https://fixture.supabase.co/functions/v1/download?app=x"))
		XCTAssertFalse(trusted("https://other.supabase.co/functions/v1/source"))
		XCTAssertFalse(trusted("https://getaccretion.app.evil.invalid/source.json"))
	}

	func testPlainHTTPIsNeverTrusted() {
		XCTAssertFalse(trusted("http://getaccretion.app/source.json"))
		XCTAssertFalse(trusted("http://raw.githubusercontent.com/AccretionMods/mods/main/mods.json"))
	}
}
