//
//  AccretionTouches.swift
//  Accretion
//

import SwiftUI
import UIKit

// MARK: - Small touches
/// A quick pop and a light tap when `on` turns true (Like, Save). Reduce Motion: the tap only.
struct AccretionPop: ViewModifier {
	let on: Bool

	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@State private var _scale: CGFloat = 1

	func body(content: Content) -> some View {
		content
			.scaleEffect(_scale)
			.onChange(of: on) { isOn in
				guard isOn else { return }
				UIImpactFeedbackGenerator(style: .light).impactOccurred()
				guard !_reduceMotion else { return }
				withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { _scale = 1.18 }
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
					withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { _scale = 1 }
				}
			}
	}
}

/// Counts roll to their new number (iOS 17 and later; earlier versions just change)
struct AccretionNumberRoll: ViewModifier {
	let value: Int

	func body(content: Content) -> some View {
		if #available(iOS 17.0, *) {
			content
				.contentTransition(.numericText(value: Double(value)))
				.animation(.easeOut(duration: 0.25), value: value)
		} else {
			content
		}
	}
}

extension View {
	func accretionPop(_ on: Bool) -> some View { modifier(AccretionPop(on: on)) }
	func accretionNumberRoll(_ value: Int) -> some View { modifier(AccretionNumberRoll(value: value)) }
}

enum AccretionHaptics {
	/// A soft tap, for a finished pull to refresh
	static func refreshed() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}
