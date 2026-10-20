//
//  AccretionLaunchView.swift
//  Accretion
//

import SwiftUI

// MARK: - Launch animation
/// Plays once on a fresh start, over the first screen (which keeps loading underneath): the stars
/// drift in, the rings are pulled into orbit, the star flashes, the name appears, then the whole
/// thing fades away. About a second; a tap skips it. With Reduce Motion it shows the finished mark
/// and fades. The launch screen (Launch Screen.storyboard) is the same night sky, so nothing jumps.
struct AccretionLaunchView: View {
	var onFinish: () -> Void

	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@State private var _pulled = false
	@State private var _lit = false
	@State private var _named = false

	private static let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.75)

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
					.foregroundStyle(Color(red: 0.957, green: 0.933, blue: 0.996))
					.opacity(_named ? 1 : 0)
					.offset(y: _named ? 0 : 8)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture { onFinish() }
		.accessibilityHidden(true)
		.task { await _play() }
	}

	private func _play() async {
		if _reduceMotion {
			var still = Transaction()
			still.disablesAnimations = true
			withTransaction(still) { _pulled = true; _lit = true; _named = true }
			guard await _wait(0.6) else { return }
			onFinish()
			return
		}
		withAnimation(Self.ease) { _pulled = true }
		guard await _wait(0.45) else { return }
		withAnimation(.spring(response: 0.34, dampingFraction: 0.52)) { _lit = true }
		guard await _wait(0.15) else { return }
		withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { _named = true }
		guard await _wait(0.4) else { return }
		onFinish()
	}

	/// False when the view went away (skipped with a tap) before the time was up
	private func _wait(_ seconds: Double) async -> Bool {
		(try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))) != nil
	}
}
