import Foundation
import XCTest
@testable import AccretionCore

final class ArchiveCheckTests: XCTestCase {
	/// A minimal zip (stored entries, no data) with the given central-directory fields.
	private func zip(_ entries: [(name: String, symlink: Bool, size: UInt32, packed: UInt32)]) throws -> URL {
		func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
		func le32(_ v: UInt32) -> [UInt8] { le16(UInt16(v & 0xFFFF)) + le16(UInt16(v >> 16)) }
		var directory: [UInt8] = []
		for e in entries {
			let name = Array(e.name.utf8)
			let mode: UInt32 = e.symlink ? 0o120777 : 0o100644
			directory += le32(0x0201_4b50) + le16(0x031E) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
			directory += le32(0) + le32(e.packed) + le32(e.size)
			directory += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0)
			directory += le32(mode << 16) + le32(0) + name
		}
		let end = le32(0x0605_4b50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
			+ le32(UInt32(directory.count)) + le32(0) + le16(0)
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
		try Data(directory + end).write(to: url)
		addTeardownBlock { try? FileManager.default.removeItem(at: url) }
		return url
	}

	func testNormalIPAPasses() throws {
		let url = try zip([("Payload/", false, 0, 0), ("Payload/App.app/App", false, 1000, 400), ("Payload/App.app/Info.plist", false, 900, 300)])
		let entries = try ArchiveCheck.zipEntries(at: url)
		XCTAssertEqual(entries.map(\.name), ["Payload/", "Payload/App.app/App", "Payload/App.app/Info.plist"])
		XCTAssertNoThrow(try ArchiveCheck.check(entries))
	}

	func testEscapingPathsAreRefused() throws {
		for bad in ["../Documents/Recipes/x/Tweaks/x.dylib", "Payload/../../escape", "/var/mobile/x", "Payload\\..\\x", ".."] {
			let entries = try ArchiveCheck.zipEntries(at: try zip([(bad, false, 10, 10)]))
			XCTAssertThrowsError(try ArchiveCheck.check(entries), bad) { XCTAssertEqual($0 as? ArchiveCheck.Failure, .unsafePath(bad)) }
		}
		XCTAssertTrue(ArchiveCheck.isSafe("Payload/App.app/..data/file"), "dots inside a name are fine")
	}

	func testWritingThroughAContainedSymlinkIsRefused() throws {
		let entries = try ArchiveCheck.zipEntries(at: try zip([("Payload/link", true, 20, 20), ("Payload/link/x.dylib", false, 10, 10)]))
		XCTAssertTrue(entries[0].isSymlink)
		XCTAssertThrowsError(try ArchiveCheck.check(entries)) { XCTAssertEqual($0 as? ArchiveCheck.Failure, .throughSymlink("Payload/link")) }
		let harmless = try ArchiveCheck.zipEntries(at: try zip([("Payload/A.framework/Current", true, 1, 1), ("Payload/A.framework/A", false, 10, 10)]))
		XCTAssertNoThrow(try ArchiveCheck.check(harmless), "a symlink nothing is written through is allowed")
	}

	func testZipBombIsRefused() throws {
		let entries = try ArchiveCheck.zipEntries(at: try zip([("Payload/big", false, 3_000_000_000, 1_000_000)]))
		XCTAssertThrowsError(try ArchiveCheck.check(entries)) { XCTAssertEqual($0 as? ArchiveCheck.Failure, .tooBig) }
	}

	func testNotAZipIsRefused() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try Data("not a zip".utf8).write(to: url)
		addTeardownBlock { try? FileManager.default.removeItem(at: url) }
		XCTAssertThrowsError(try ArchiveCheck.zipEntries(at: url)) { XCTAssertEqual($0 as? ArchiveCheck.Failure, .notAZip) }
	}
}
