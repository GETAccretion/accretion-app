import Foundation
import XCTest
@testable import AccretionCore

final class UpdateSourcesTests: XCTestCase {
	private func trusted(_ string: String) -> Bool { UpdateSources.isAccretionCatalog(URL(string: string)!) }

	func testAccretionCatalogsAreTrusted() {
		XCTAssertTrue(trusted("https://getaccretion.app/source.json"))
		XCTAssertTrue(trusted("https://getaccretion.app/curated.json"))
		XCTAssertTrue(trusted("https://raw.githubusercontent.com/AccretionMods/mods/main/mods.json"))
		XCTAssertTrue(trusted("https://raw.githubusercontent.com/GETAccretion/accretion-app/main/app-repo.json"))
		XCTAssertTrue(trusted("https://bbcjpinhvlxocjxlyplt.supabase.co/functions/v1/source?name=store&key=x"))
	}

	func testOtherSourcesAreNot() {
		XCTAssertFalse(trusted("https://some-repo.invalid/apps.json"))
		XCTAssertFalse(trusted("http://getaccretion.app/source.json"), "plain http")
		XCTAssertFalse(trusted("https://getaccretion.app.evil.invalid/source.json"))
		XCTAssertFalse(trusted("https://raw.githubusercontent.com/someone/AccretionMods/mods/x.json"))
		XCTAssertFalse(trusted("https://raw.githubusercontent.com/AccretionModsFake/mods/x.json"))
		XCTAssertFalse(trusted("https://bbcjpinhvlxocjxlyplt.supabase.co/functions/v1/download?app=x"))
	}
}
