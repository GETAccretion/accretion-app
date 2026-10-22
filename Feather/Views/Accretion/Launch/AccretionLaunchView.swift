//
//  AccretionLaunchView.swift
//  Accretion
//

import QuartzCore
import SwiftUI

// MARK: - Launch animation
/// Plays once on a fresh start, over the first screen (which loads underneath): the stars drift in,
/// the rings are pulled into orbit, the star flashes, the name appears, then a bar under it fills
/// with the warm-up's steps (AccretionWarmUp: catalogue, new apps, shelves, icons; at most 6 s in
/// all) and the whole thing fades away, so Discover opens complete. It can't be skipped: cutting it
/// short showed Discover before its data was in. With Reduce Motion it shows the finished mark and
/// the bar without movement. The launch screen (Launch Screen.storyboard) is the same night sky, so
/// nothing jumps.
struct AccretionLaunchView: View {
	var onFinish: () -> Void

	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@StateObject private var _warmUp = AccretionWarmUp()
	@State private var _hitches = AccretionLaunchHitches()
	@State private var _pulled = false
	@State private var _lit = false
	@State private var _named = false
	@State private var _barShown = false
	/// What the bar shows: follows the warm-up at most `fillRate` per second, so it always fills smoothly and
	/// each step's text is readable, even when the warm-up was done before the bar appeared
	@State private var _shown = 0.0

	private static let fillRate = 0.9
	private static let tick = 1.0 / 30

	private static let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.75)
	private static let text = Color(red: 0.957, green: 0.933, blue: 0.996)

	var body: some View {
		ZStack {
			AccretionNightSky()
			AccretionStarfield()
				.scaleEffect(_pulled ? 1 : 1.18)
				.opacity(_pulled ? 1 : 0)
			VStack(spacing: 26) {
				AccretionMark(size: 260, pulled: _pulled, lit: _lit)
				Text(verbatim: "Accretion")
					.font(.accretionDisplay(30))
					.foregroundStyle(Self.text)
					.opacity(_named ? 1 : 0)
					.offset(y: _named ? 0 : 8)
				AccretionLaunchProgress(progress: _shown, step: _warmUp.step(at: _shown), animated: !_reduceMotion)
					.opacity(_barShown ? 1 : 0)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(String.localized("Loading Accretion"))
		.accessibilityValue(_warmUp.step)
		.task { await _play() }
	}

	private func _play() async {
		let warmUp = _warmUp
		_hitches.start { warmUp.step }
		async let warmed: Void = _warmUp.run()
		if _reduceMotion {
			var still = Transaction()
			still.disablesAnimations = true
			withTransaction(still) { _pulled = true; _lit = true; _named = true; _barShown = true }
		} else {
			withAnimation(Self.ease) { _pulled = true }
			await _wait(0.45)
			withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) { _lit = true }
			await _wait(0.15)
			withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { _named = true }
			await _wait(0.2)
			withAnimation(.easeOut(duration: 0.25)) { _barShown = true }
		}
		// the bar catches up with the warm-up at its own pace and ends full
		var last = CACurrentMediaTime()
		while _shown < 1 {
			let now = CACurrentMediaTime()
			let next = min(_warmUp.progress, _shown + Self.fillRate * min(now - last, 0.1))
			last = now
			if next > _shown {
				if _reduceMotion { _shown = next } else { withAnimation(.linear(duration: Self.tick)) { _shown = next } }
			}
			await _wait(Self.tick)
		}
		await warmed
		// let the bar be seen full before the fade
		await _wait(_reduceMotion ? 0.2 : 0.35)
		_hitches.stop()
		onFinish()
	}

	private func _wait(_ seconds: Double) async {
		try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
	}
}

// MARK: - Progress bar
/// A thin bar in the mark's ring colours with what is being loaded under it, e.g. "Loading icons 12 of 24"
struct AccretionLaunchProgress: View {
	let progress: Double
	let step: String
	var animated = true

	private static let width: CGFloat = 200

	var body: some View {
		VStack(spacing: 10) {
			ZStack(alignment: .leading) {
				Capsule()
					.fill(Color.white.opacity(0.12))
				Capsule()
					.fill(LinearGradient(colors: AccretionMark.ringColors.reversed(), startPoint: .leading, endPoint: .trailing))
					.frame(width: max(6, Self.width * progress))
			}
			.frame(width: Self.width, height: 5)

			HStack(spacing: 8) {
				Text(verbatim: step)
					.contentTransition(.opacity)
					.animation(animated ? .easeOut(duration: 0.2) : nil, value: step)
				Spacer(minLength: 0)
				Text(verbatim: "\(Int((progress * 100).rounded()))%")
					.monospacedDigit()
			}
			.font(.accretionMono(11.5, weight: .regular))
			.foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.996).opacity(0.7))
			.lineLimit(1)
			.frame(width: Self.width)
		}
	}
}
