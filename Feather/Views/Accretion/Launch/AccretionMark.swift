//
//  AccretionMark.swift
//  Accretion
//

import SwiftUI

// MARK: - Brand mark
/// The ringed star from the app icon, drawn as vectors: four rings tilted 17° (violet to cream)
/// around a bright star. Colours and proportions are sampled from the icon.
/// `pulled` false: the rings sit wide and faint, and the launch animation pulls them into orbit
/// (inner ring first). `lit` false: the star is small and dim; true: it flashes and settles.
struct AccretionMark: View {
	var size: CGFloat
	var pulled = true
	var lit = true

	/// Outer to inner: half-widths and half-heights as a share of `size`, and colours
	private static let rings: [(rx: CGFloat, ry: CGFloat, color: Color)] = [
		(0.420, 0.147, _rgb(0x956FFF)),
		(0.365, 0.133, _rgb(0xD195FF)),
		(0.310, 0.120, _rgb(0xFFD9FF)),
		(0.250, 0.105, _rgb(0xFEFECD)),
	]
	private static let tilt: Double = 17
	static let starColor = _rgb(0xFFF8EE)
	static let glowColor = _rgb(0xFFDDB3)

	var body: some View {
		ZStack {
			Circle()
				.fill(RadialGradient(colors: [Self.glowColor.opacity(0.55), Self.glowColor.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.2))
				.frame(width: size * 0.4, height: size * 0.4)
				.scaleEffect(lit ? 1 : 0.5)
				.opacity(lit ? 1 : 0)
			ForEach(Array(Self.rings.enumerated()), id: \.offset) { index, ring in
				Ellipse()
					.stroke(ring.color, lineWidth: max(1, size * 0.012))
					.frame(width: size * ring.rx * 2, height: size * ring.ry * 2)
					.rotationEffect(.degrees(pulled ? Self.tilt : Self.tilt - 25))
					.scaleEffect(pulled ? 1 : 2.4)
					.opacity(pulled ? 1 : 0)
					// the inner ring lands first, the outer one last
					.animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.56).delay(Double(Self.rings.count - 1 - index) * 0.06), value: pulled)
			}
			Circle()
				.fill(Self.starColor)
				.frame(width: size * 0.128, height: size * 0.128)
				.scaleEffect(lit ? 1 : 0.35)
				.opacity(lit ? 1 : 0.45)
		}
		.frame(width: size, height: size * 0.55)
	}

	fileprivate static func _rgb(_ hex: UInt32) -> Color {
		Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
	}
}

// MARK: - Night sky
/// The icon's background: deep navy to violet, with a fixed scatter of small stars
struct AccretionNightSky: View {
	static let top = AccretionMark._rgb(0x080A20)
	static let bottom = AccretionMark._rgb(0x251153)

	var body: some View {
		LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
			.ignoresSafeArea()
	}
}

/// Small stars at fixed positions (the same on every launch)
struct AccretionStarfield: View {
	var body: some View {
		Canvas { context, canvas in
			var seed: UInt64 = 0x5EED_ACC2
			func next() -> CGFloat {
				seed = seed &* 6364136223846793005 &+ 1442695040888963407
				return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
			}
			let count = Int(canvas.width * canvas.height / 4200)
			for _ in 0..<count {
				let point = CGPoint(x: next() * canvas.width, y: next() * canvas.height)
				let radius = next() < 0.8 ? 0.6 : 1.1
				let alpha = 0.3 + next() * 0.5
				context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(alpha)))
			}
		}
		.ignoresSafeArea()
	}
}
