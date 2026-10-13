//
//  AccretionDrift.swift
//  Accretion
//
//  Core: pure logic with no app dependencies, unit-tested by CoreTests (CoreTests/run.sh).
//

import CoreGraphics
import Foundation

/// The website's `@keyframes drift` for the background light: 0% (0, 0), 50% (6vmax, -4vmax),
/// 100% (-5vmax, 5vmax), 40 s each way, alternating, eased in and out between keyframes like CSS's
/// ease-in-out.
enum AccretionDrift {
	static let duration: TimeInterval = 40

	/// The offset at `time` (seconds) for a screen whose longer side is `vmax` points
	static func offset(at time: TimeInterval, vmax: CGFloat) -> CGPoint {
		let cycle = time.truncatingRemainder(dividingBy: duration * 2)
		let progress = cycle <= duration ? cycle / duration : (duration * 2 - cycle) / duration
		let ease = { (x: Double) in (1 - cos(Double.pi * x)) / 2 }
		let a = CGPoint.zero, b = CGPoint(x: 6, y: -4), c = CGPoint(x: -5, y: 5)
		let (from, to, k) = progress <= 0.5 ? (a, b, ease(progress * 2)) : (b, c, ease(progress * 2 - 1))
		return CGPoint(
			x: (from.x + (to.x - from.x) * k) / 100 * vmax,
			y: (from.y + (to.y - from.y) * k) / 100 * vmax
		)
	}
}
