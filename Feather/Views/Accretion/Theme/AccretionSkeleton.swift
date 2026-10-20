//
//  AccretionSkeleton.swift
//  Accretion
//

import SwiftUI

// MARK: - Loading placeholders
/// The shape of what's loading, in the raised surface colour, with a soft light passing over it
/// (still with Reduce Motion). Hidden from VoiceOver; the screen says "Loading" once instead.
struct AccretionShimmer: ViewModifier {
	@Environment(\.accessibilityReduceMotion) private var _reduceMotion

	func body(content: Content) -> some View {
		content
			.overlay {
				if !_reduceMotion {
					TimelineView(.animation) { context in
						let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
						GeometryReader { geo in
							LinearGradient(colors: [.clear, AccretionTheme.fg.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
								.frame(width: geo.size.width * 0.6)
								.offset(x: -geo.size.width * 0.6 + geo.size.width * 1.6 * phase)
						}
					}
					.allowsHitTesting(false)
				}
			}
			.mask { content }
	}
}

extension View {
	func accretionShimmer() -> some View { modifier(AccretionShimmer()) }
}

/// A bar or block of placeholder
struct AccretionSkeletonBlock: View {
	var width: CGFloat? = nil
	var height: CGFloat
	var radius: CGFloat = 6

	var body: some View {
		RoundedRectangle(cornerRadius: radius, style: .continuous)
			.fill(AccretionTheme.raised)
			.frame(width: width, height: height)
	}
}

/// Discover before the store has loaded: two shelves of app rows
struct AccretionDiscoverSkeleton: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 28) {
			ForEach(0..<2, id: \.self) { _ in
				VStack(alignment: .leading, spacing: 12) {
					AccretionSkeletonBlock(width: 150, height: 18)
					ForEach(0..<3, id: \.self) { row in
						HStack(spacing: 12) {
							AccretionSkeletonBlock(width: 52, height: 52, radius: 12)
							VStack(alignment: .leading, spacing: 8) {
								AccretionSkeletonBlock(width: row == 1 ? 120 : 170, height: 12)
								AccretionSkeletonBlock(width: row == 2 ? 90 : 130, height: 10)
							}
						}
						.frame(height: 64)
					}
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.top, 12)
		.accretionShimmer()
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(String.localized("Loading"))
	}
}

/// An app page before its details have loaded: screenshots, then a few lines of text
struct AccretionAppPageSkeleton: View {
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			AccretionSkeletonBlock(width: 120, height: 16)
			HStack(spacing: 12) {
				ForEach(0..<3, id: \.self) { _ in
					AccretionSkeletonBlock(width: 120, height: 240, radius: 18)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.clipped()
			VStack(alignment: .leading, spacing: 9) {
				AccretionSkeletonBlock(height: 12)
				AccretionSkeletonBlock(height: 12)
				AccretionSkeletonBlock(width: 180, height: 12)
			}
			.padding(.top, 6)
		}
		.accretionShimmer()
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(String.localized("Loading details"))
	}
}
