//
//  AccretionTheme.swift
//  Accretion
//

import SwiftUI
import UIKit

// MARK: - Colours
/// The Accretion web store's design tokens (site/style.css in getaccretion.github.io), with the
/// same light-mode values, so the app and the store look like one product.
enum AccretionTheme {
	static let bg = _dynamic(dark: 0x07070D, light: 0xF7F6FC)
	static let surface = _dynamic(dark: 0x0F0E1A, light: 0xFFFFFF)
	static let raised = _dynamic(dark: 0x17152A, light: 0xF0EEF9)
	static let line = _dynamic(dark: 0x262145, light: 0xDFDAF2)
	static let fg = _dynamic(dark: 0xECEAFF, light: 0x15122B)
	static let muted = _dynamic(dark: 0x8B87B3, light: 0x625E85)
	static let accent = _dynamic(dark: 0x8B5CF6, light: 0x6D3FE0)
	static let accent2 = _dynamic(dark: 0x22D3EE, light: 0x0E8FB0)
	static let good = _dynamic(dark: 0x34D399, light: 0x078A5E)
	static let warn = _dynamic(dark: 0xF59E0B, light: 0xB76A00)

	static let radius: CGFloat = 14

	private static func _dynamic(dark: UInt32, light: UInt32) -> Color {
		Color(UIColor { traits in
			let hex = traits.userInterfaceStyle == .light ? light : dark
			return UIColor(
				red: CGFloat((hex >> 16) & 0xFF) / 255,
				green: CGFloat((hex >> 8) & 0xFF) / 255,
				blue: CGFloat(hex & 0xFF) / 255,
				alpha: 1
			)
		})
	}
}

// MARK: - Type
extension Font {
	/// Headings, like the store's Sora display face
	static func accretionDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
		.system(size: size, weight: weight, design: .rounded)
	}
	/// Badges and small labels, like the store's JetBrains Mono
	static func accretionMono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
		.system(size: size, weight: weight, design: .monospaced)
	}
}

// MARK: - Pieces
/// Small uppercase pill: "new", "update", "Accretion Mod", "core"
struct AccretionBadge: View {
	let text: String
	var color: Color = AccretionTheme.good

	var body: some View {
		Text(verbatim: text.uppercased())
			.font(.accretionMono(10))
			.tracking(0.6)
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.foregroundStyle(color)
			.background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
	}
}

/// Card surface with the store's border and radius
struct AccretionCard: ViewModifier {
	func body(content: Content) -> some View {
		content
			.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: AccretionTheme.radius, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: AccretionTheme.radius, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}
}

extension View {
	func accretionCard() -> some View { modifier(AccretionCard()) }

	/// The store's page background: near-black with a faint grid
	func accretionBackground() -> some View {
		background(
			ZStack {
				AccretionTheme.bg
				Canvas { context, size in
					let step: CGFloat = 32
					var path = Path()
					stride(from: 0, through: size.width, by: step).forEach { x in
						path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
					}
					stride(from: 0, through: size.height, by: step).forEach { y in
						path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
					}
					context.stroke(path, with: .color(AccretionTheme.fg.opacity(0.035)), lineWidth: 1)
				}
			}
			.ignoresSafeArea()
		)
	}
}

/// Primary pill button in the store's accent colour
struct AccretionButtonStyle: ButtonStyle {
	var prominent = true

	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(.system(size: 15, weight: .semibold))
			.padding(.horizontal, 16)
			.padding(.vertical, 9)
			.foregroundStyle(prominent ? Color.white : AccretionTheme.fg)
			.background(
				prominent ? AccretionTheme.accent : AccretionTheme.raised,
				in: RoundedRectangle(cornerRadius: 11, style: .continuous)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 11, style: .continuous)
					.stroke(prominent ? Color.clear : AccretionTheme.line, lineWidth: 1)
			)
			.opacity(configuration.isPressed ? 0.75 : 1)
	}
}
