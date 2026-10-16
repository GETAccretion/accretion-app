import Foundation
import XCTest
@testable import AccretionCore

final class ServerMessageTests: XCTestCase {
	func testReadsTheServersSentence() {
		XCTAssertEqual(ServerMessage.from(Data(#"{"message":"Too many downloads. Try again in a few minutes."}"#.utf8)), "Too many downloads. Try again in a few minutes.")
	}

	func testIgnoresAnythingElse() {
		XCTAssertNil(ServerMessage.from(nil))
		XCTAssertNil(ServerMessage.from(Data("<html>error</html>".utf8)))
		XCTAssertNil(ServerMessage.from(Data(#"{"message":"   "}"#.utf8)))
		XCTAssertNil(ServerMessage.from(Data(#"{"error":"x"}"#.utf8)))
		XCTAssertNil(ServerMessage.from(Data(("{\"message\":\"" + String(repeating: "a", count: 400) + "\"}").utf8)))
	}

	func testReadsAFileOnlyWhenSmall() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		addTeardownBlock { try? FileManager.default.removeItem(at: url) }
		try Data(#"{"message":"This app or version isn't in the store."}"#.utf8).write(to: url)
		XCTAssertEqual(ServerMessage.from(fileAt: url), "This app or version isn't in the store.")
		try Data(repeating: 65, count: 10_000).write(to: url)
		XCTAssertNil(ServerMessage.from(fileAt: url))
	}
}
