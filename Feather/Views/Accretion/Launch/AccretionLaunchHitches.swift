//
//  AccretionLaunchHitches.swift
//  Accretion
//

import OSLog
import QuartzCore

// MARK: - Opening hitch log
/// Counts the frames the opening drops, per warm-up step, and writes one line to the device log when it
/// ends (category "Launch", public), e.g. "Opening 2.41 s, 120 Hz, 3 hitches, longest 48 ms: Arranging
/// the shelves 2 (48 ms), Loading icons 1 (17 ms)". Read it with the device log (Accretion Link's syslog,
/// or Console on a Mac) to see which step stutters on a real phone.
@MainActor
final class AccretionLaunchHitches: NSObject {
	private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Accretion", category: "Launch")

	private var _link: CADisplayLink?
	private var _last: CFTimeInterval = 0
	private var _started: CFTimeInterval = 0
	private var _frame: CFTimeInterval = 1.0 / 60
	private var _step: () -> String = { "" }
	/// step -> (hitches, longest in seconds), in the order the steps came
	private var _byStep: [(step: String, count: Int, longest: CFTimeInterval)] = []

	func start(step: @escaping () -> String) {
		_step = step
		_started = CACurrentMediaTime()
		let link = CADisplayLink(target: self, selector: #selector(_tick(_:)))
		link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
		link.add(to: .main, forMode: .common)
		_link = link
	}

	func stop() {
		guard let link = _link else { return }
		link.invalidate()
		_link = nil
		let total = _byStep.reduce(0) { $0 + $1.count }
		let longest = _byStep.map(\.longest).max() ?? 0
		let steps = _byStep.map { "\($0.step) \($0.count) (\(Int($0.longest * 1000)) ms)" }.joined(separator: ", ")
		let line = String(format: "Opening %.2f s, %d Hz, %d hitches, longest %d ms", CACurrentMediaTime() - _started, Int((1 / _frame).rounded()), total, Int(longest * 1000))
		Self.log.notice("\(line, privacy: .public)\(steps.isEmpty ? "" : ": " + steps, privacy: .public)")
	}

	@objc private func _tick(_ link: CADisplayLink) {
		let frame = link.targetTimestamp - link.timestamp
		if frame > 0 { _frame = frame }
		defer { _last = link.timestamp }
		guard _last > 0 else { return }
		let gap = link.timestamp - _last
		// a frame shown more than half a frame late is a hitch the eye can catch
		guard gap > _frame * 1.5 else { return }
		let step = _step()
		if let index = _byStep.firstIndex(where: { $0.step == step }) {
			_byStep[index].count += 1
			_byStep[index].longest = max(_byStep[index].longest, gap)
		} else {
			_byStep.append((step, 1, gap))
		}
	}
}
