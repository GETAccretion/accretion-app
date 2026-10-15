import Foundation
import XCTest
@testable import AccretionCore

final class ArchiveEntryPathTests: XCTestCase {
	func testOrdinaryIPAEntriesStayInside() {
		for name in [
			"Payload/",
			"Payload/App.app/Info.plist",
			"Payload/App.app/Frameworks/A.framework/A",
			"./Payload/App.app/x",
			"Payload/App.app/../App.app/x",
			"Payload\\App.app\\x",
		] {
			XCTAssertTrue(ArchiveEntryPath.isContained(name), name)
		}
	}

	func testEntriesThatClimbOutAreRefused() {
		for name in [
			"../Documents/Recipes/com.victim/Tweaks/x.dylib",
			"Payload/../../Library/Preferences/app.plist",
			"..",
			"../",
			"..\\Documents\\x",
			"/Payload/App.app/x",
			"/",
			"",
			"Payload/\0/x",
		] {
			XCTAssertFalse(ArchiveEntryPath.isContained(name), name)
		}
	}

	func testFirstEscapingNamesTheOffender() {
		XCTAssertNil(ArchiveEntryPath.firstEscaping(["Payload/", "Payload/App.app/x"]))
		XCTAssertEqual(ArchiveEntryPath.firstEscaping(["Payload/", "../x", "../../y"]), "../x")
	}
}
