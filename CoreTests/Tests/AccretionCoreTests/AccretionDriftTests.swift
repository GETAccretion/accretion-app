import CoreGraphics
import XCTest
@testable import AccretionCore

final class AccretionDriftTests: XCTestCase {
	private let vmax: CGFloat = 1000 // 1vmax = 10 points

	func testKeyframes() {
		// 0%: still
		XCTAssertEqual(AccretionDrift.offset(at: 0, vmax: vmax), .zero)
		// 50% (20 s): (6vmax, -4vmax)
		let middle = AccretionDrift.offset(at: 20, vmax: vmax)
		XCTAssertEqual(middle.x, 60, accuracy: 0.001)
		XCTAssertEqual(middle.y, -40, accuracy: 0.001)
		// 100% (40 s): (-5vmax, 5vmax)
		let end = AccretionDrift.offset(at: 40, vmax: vmax)
		XCTAssertEqual(end.x, -50, accuracy: 0.001)
		XCTAssertEqual(end.y, 50, accuracy: 0.001)
	}

	func testAlternatesBack() {
		// animation-direction: alternate, so 60 s mirrors 20 s and 80 s is back at the start
		let forward = AccretionDrift.offset(at: 20, vmax: vmax)
		let back = AccretionDrift.offset(at: 60, vmax: vmax)
		XCTAssertEqual(forward.x, back.x, accuracy: 0.001)
		XCTAssertEqual(forward.y, back.y, accuracy: 0.001)
		XCTAssertEqual(AccretionDrift.offset(at: 80, vmax: vmax).x, 0, accuracy: 0.001)
	}

	func testEasesInAndOut() {
		// ease-in-out: a quarter of the way through the first half moves less than a quarter
		let quarter = AccretionDrift.offset(at: 5, vmax: vmax)
		XCTAssertLessThan(quarter.x, 60 * 0.25)
		XCTAssertGreaterThan(quarter.x, 0)
	}
}
