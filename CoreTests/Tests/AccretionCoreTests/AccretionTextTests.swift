import XCTest
@testable import AccretionCore

final class AccretionTextTests: XCTestCase {
	private func links(_ text: String) -> [URL] {
		accretionLinked(text).runs.compactMap(\.link)
	}

	func testHttpsLinksBecomeLinks() {
		XCTAssertEqual(links("see https://getaccretion.github.io/#/feed now"), [URL(string: "https://getaccretion.github.io/#/feed")!])
	}

	func testOnlyHttps() {
		XCTAssertEqual(links("plain http://example.com is not a link"), [])
		XCTAssertEqual(links("no links here, just @someone"), [])
	}

	func testTextIsUnchanged() {
		let text = "two https://a.example and https://b.example links"
		XCTAssertEqual(String(accretionLinked(text).characters), text)
		XCTAssertEqual(links(text).count, 2)
	}
}
