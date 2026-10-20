//
//  AccretionOrbitProgress.swift
//  Accretion
//

import SwiftUI

// MARK: - Orbit progress
/// Progress drawn as the logo's tilted rings around a centre (an app icon). Each ring fills on its
/// own, outer first, as if pulled in. The back half of every ring passes behind the centre and the
/// front half in front of it. `done` makes the centre flash like the logo's star. `sweeping` turns
/// one ring into a looping arc, for a step with no percentage (signing).
struct AccretionOrbitProgress<Center: View>: View {
	/// Fill of each ring, outer to inner, 0...1
	var progress: [Double]
	var done = false
	/// A ring that loops instead of filling, or nil
	var sweeping: Int? = nil
	/// Width of the outer ring
	var size: CGFloat
	@ViewBuilder var center: () -> Center

	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@State private var _pop = false

	/// Outer to inner, as a share of `size`
	private static var radii: [(rx: CGFloat, ry: CGFloat)] { [(0.50, 0.23), (0.42, 0.20), (0.34, 0.17)] }
	private static var colors: [Color] { [AccretionMark.ringColors[0], AccretionMark.ringColors[1], AccretionMark.ringColors[3]] }

	var body: some View {
		Group {
			if sweeping != nil, !_reduceMotion {
				TimelineView(.animation) { context in
					_orbit(phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4)
				}
			} else {
				_orbit(phase: nil)
			}
		}
		.frame(width: size, height: size * 0.56)
		.onChange(of: done) { isDone in
			guard isDone, !_reduceMotion else { return }
			withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { _pop = true }
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
				withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _pop = false }
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(done ? String.localized("Done") : String.localized("In progress"))
	}

	private func _orbit(phase: Double?) -> some View {
		ZStack {
			ForEach(0..<Self.radii.count, id: \.self) { _ring($0, front: false, phase: phase) }
			Circle()
				.fill(RadialGradient(colors: [AccretionMark.glowColor.opacity(0.7), AccretionMark.glowColor.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.3))
				.frame(width: size * 0.6, height: size * 0.6)
				.scaleEffect(done ? 1 : 0.4)
				.opacity(done ? 1 : 0)
				.animation(.spring(response: 0.45, dampingFraction: 0.6), value: done)
			center()
				.scaleEffect(_pop ? 1.1 : 1)
			ForEach(0..<Self.radii.count, id: \.self) { _ring($0, front: true, phase: phase) }
		}
	}

	/// One half of a ring: the path starts at the right end and runs clockwise, so 0...0.5 is the
	/// lower (front) half and 0.5...1 the upper (back) half
	private func _ring(_ index: Int, front: Bool, phase: Double?) -> some View {
		let radius = Self.radii[index]
		let color = Self.colors[index]
		let width = max(1.5, size * 0.022)
		var from = 0.0
		var to = done ? 1 : min(1, max(0, index < progress.count ? progress[index] : 0))
		if index == sweeping, !done {
			if let phase {
				// an arc that enters at the start and leaves at the end of the ring
				to = min(1, phase * 1.3)
				from = max(0, phase * 1.3 - 0.3)
			} else {
				to = 1 // Reduce Motion: the whole ring, dimmed below
			}
		}
		let low = front ? 0.0 : 0.5
		let high = front ? 0.5 : 1.0
		let start = min(max(from, low), high)
		let end = min(max(to, low), high)
		return ZStack {
			Ellipse()
				.trim(from: low, to: high)
				.stroke(color.opacity(0.16), lineWidth: width)
			Ellipse()
				.trim(from: start, to: end)
				.stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
				.opacity(end > start ? (index == sweeping && phase == nil && !done ? 0.5 : 1) : 0)
		}
		.frame(width: size * radius.rx * 2, height: size * radius.ry * 2)
		.rotationEffect(.degrees(AccretionMark.tilt))
		.animation(phase == nil ? .easeOut(duration: 0.35) : nil, value: to)
	}
}
