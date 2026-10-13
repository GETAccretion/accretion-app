//
//  AccretionTheme.swift
//  Accretion
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Colours
/// The Accretion web store's design tokens, from AccretionTokens.swift (generated from
/// design/tokens.json in getaccretion.github.io, the same file that writes the website's colours),
/// so the app and the store look like one product.
enum AccretionTheme {
	static let bg = _dynamic(AccretionTokens.bg)
	static let surface = _dynamic(AccretionTokens.surface)
	static let raised = _dynamic(AccretionTokens.raised)
	static let line = _dynamic(AccretionTokens.line)
	static let fg = _dynamic(AccretionTokens.fg)
	static let muted = _dynamic(AccretionTokens.muted)
	static let accent = _dynamic(AccretionTokens.accent)
	static let accent2 = _dynamic(AccretionTokens.accent2)
	static let good = _dynamic(AccretionTokens.good)
	static let warn = _dynamic(AccretionTokens.warn)
	static let bad = _dynamic(AccretionTokens.bad)
	static let star = Color(red: 245.0 / 255, green: 184.0 / 255, blue: 59.0 / 255)
	/// color-mix(accent 55%, accent-2): the far end of the primary button's gradient
	static let accentMix = _dynamic(dark: 0x5C93F2, light: 0x4568C8)

	static let radius: CGFloat = AccretionTokens.radius

	/// The store's headline and stat numbers: text fading from the foreground into the accents
	static let headline = LinearGradient(
		stops: [
			.init(color: fg, location: 0.3),
			.init(color: _dynamic(dark: 0x6C86F3, light: 0x5251D6), location: 1),
		],
		startPoint: .leading,
		endPoint: .trailing
	)

	private static func _dynamic(dark: UInt32, light: UInt32) -> Color {
		Color(uiDynamic(dark: dark, light: light))
	}

	private static func _dynamic(_ pair: (dark: UInt32, light: UInt32)) -> Color {
		_dynamic(dark: pair.dark, light: pair.light)
	}

	/// UIKit version, for appearance proxies (navigation bars, tab bar)
	static func uiDynamic(dark: UInt32, light: UInt32) -> UIColor {
		UIColor { traits in
			let hex = traits.userInterfaceStyle == .light ? light : dark
			return UIColor(
				red: CGFloat((hex >> 16) & 0xFF) / 255,
				green: CGFloat((hex >> 8) & 0xFF) / 255,
				blue: CGFloat(hex & 0xFF) / 255,
				alpha: 1
			)
		}
	}

	// MARK: App-wide UIKit appearance
	/// Navigation titles in the store's display style and colours, set once at launch so every
	/// screen (including Feather's own) picks them up.
	static func applyAppearance() {
		let fg = uiDynamic(dark: AccretionTokens.fg.dark, light: AccretionTokens.fg.light)
		func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
			let base = UIFont.systemFont(ofSize: size, weight: weight)
			guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
			return UIFont(descriptor: descriptor, size: size)
		}

		let standard = UINavigationBarAppearance()
		standard.configureWithDefaultBackground()
		standard.largeTitleTextAttributes = [.font: rounded(34, .heavy), .foregroundColor: fg]
		standard.titleTextAttributes = [.font: rounded(17, .bold), .foregroundColor: fg]

		let edge = UINavigationBarAppearance()
		edge.configureWithTransparentBackground()
		edge.largeTitleTextAttributes = standard.largeTitleTextAttributes
		edge.titleTextAttributes = standard.titleTextAttributes

		UINavigationBar.appearance().standardAppearance = standard
		UINavigationBar.appearance().compactAppearance = standard
		UINavigationBar.appearance().scrollEdgeAppearance = edge

		// tab bar: the store's page colour with a hairline, violet when selected
		let tabs = UITabBarAppearance()
		tabs.configureWithDefaultBackground()
		tabs.backgroundColor = uiDynamic(dark: AccretionTokens.bg.dark, light: AccretionTokens.bg.light).withAlphaComponent(0.92)
		let muted = uiDynamic(dark: AccretionTokens.muted.dark, light: AccretionTokens.muted.light)
		let accent = uiDynamic(dark: AccretionTokens.accent.dark, light: AccretionTokens.accent.light)
		for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
			item.normal.iconColor = muted
			item.normal.titleTextAttributes = [.foregroundColor: muted]
			item.selected.iconColor = accent
			item.selected.titleTextAttributes = [.foregroundColor: accent]
		}
		UITabBar.appearance().standardAppearance = tabs
		UITabBar.appearance().scrollEdgeAppearance = tabs
	}
}

// MARK: - Type
/// The store's own typefaces, bundled in Resources/Fonts (SIL Open Font License): Sora 600/700 for
/// headings and JetBrains Mono 400/500 for labels, the same weights the website loads. Registered
/// once in code, so they work wherever the build puts them; if one ever fails to load, the
/// matching system font is used instead. (A lazy static: registered once, safely from any thread.)
enum AccretionFonts {
	static let available: Set<String> = {
		var names = Set<String>()
		let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
			+ (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
		for url in urls {
			// already registered (or registered by Info.plist) is fine too
			CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
		}
		for name in ["Sora-SemiBold", "Sora-Bold", "JetBrainsMono-Regular", "JetBrainsMono-Medium"]
		where UIFont(name: name, size: 12) != nil {
			names.insert(name)
		}
		return names
	}()
}

extension Font {
	/// Headings, in the store's Sora (600 or 700, like the website)
	static func accretionDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
		let name = weight == .bold || weight == .heavy || weight == .black ? "Sora-Bold" : "Sora-SemiBold"
		guard AccretionFonts.available.contains(name) else { return .system(size: size, weight: weight, design: .rounded) }
		return .custom(name, fixedSize: size)
	}
	/// Badges and small labels, in the store's JetBrains Mono (400, or 500 for anything heavier,
	/// the nearest weight the website loads)
	static func accretionMono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
		let name = weight == .regular || weight == .light || weight == .thin || weight == .ultraLight
			? "JetBrainsMono-Regular" : "JetBrainsMono-Medium"
		guard AccretionFonts.available.contains(name) else { return .system(size: size, weight: weight, design: .monospaced) }
		return .custom(name, fixedSize: size)
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

	/// Lists and forms on the store's background instead of the system grouped grey
	func accretionList() -> some View {
		scrollContentBackground(.hidden).accretionBackground()
	}

	/// The store's page background, in the website's paint order: the colour, the faint grid
	/// (body's background-image), then the drifting light (body::before) over it.
	func accretionBackground() -> some View {
		background(
			ZStack {
				AccretionTheme.bg
				AccretionGrid()
				AccretionAmbientGlow()
			}
			.ignoresSafeArea()
		)
	}
}

/// The store's `.btn`: 40-pt tall, 10-pt corners, raised fill with a hairline border.
/// `prominent` is `.btn.primary` (accent gradient), `ghost` is `.btn.ghost` (no fill) and
/// `on` is `.btn.on` (green outline, for Liked and Saved).
struct AccretionButtonStyle: ButtonStyle {
	var prominent = true
	var ghost = false
	var on = false
	var compact = false

	func makeBody(configuration: Configuration) -> some View {
		let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
		configuration.label
			.font(.system(size: compact ? 13 : 14, weight: .semibold))
			.lineLimit(1)
			.padding(.horizontal, compact ? 12 : 14)
			.frame(minHeight: compact ? 34 : 40)
			.foregroundStyle(prominent ? Color.white : on ? AccretionTheme.good : AccretionTheme.fg)
			.background {
				if prominent {
					shape.fill(LinearGradient(colors: [AccretionTheme.accent, AccretionTheme.accentMix], startPoint: .topLeading, endPoint: .bottomTrailing))
				} else if !ghost {
					shape.fill(AccretionTheme.raised)
				}
			}
			.overlay(shape.stroke(prominent ? Color.clear : on ? AccretionTheme.good : AccretionTheme.line, lineWidth: 1))
			.contentShape(shape)
			// Accretion: a quick give under the finger, like a native button
			.opacity(configuration.isPressed ? 0.85 : 1)
			.scaleEffect(configuration.isPressed ? 0.96 : 1)
			.animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
	}
}

/// Tappable rows and cards (the store's links): dim and shrink slightly while pressed, spring back
/// on release. Looks identical to `.plain` at rest.
struct AccretionPressStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.opacity(configuration.isPressed ? 0.8 : 1)
			.scaleEffect(configuration.isPressed ? 0.98 : 1)
			.animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
	}
}

/// Light haptics for taps that change what's on screen (tabs, chips, filters)
@MainActor
enum AccretionHaptics {
	private static let _selection = UISelectionFeedbackGenerator()
	static func select() { _selection.selectionChanged() }
}

/// The store's `.sec` card: surface, 14-pt corners, and a small mono uppercase heading.
struct AccretionSection<Content: View>: View {
	let title: String?
	@ViewBuilder let content: Content

	init(_ title: String?, @ViewBuilder content: () -> Content) {
		self.title = title
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let title {
				Text(verbatim: title.uppercased())
					.font(.accretionMono(11, weight: .medium))
					.tracking(1.1)
					.foregroundStyle(AccretionTheme.muted)
			}
			content
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 16)
		.padding(.horizontal, 18)
		.accretionCard()
	}
}

/// One cell of the store's `.facts` grid: "VERSION / 4.0.0"
struct AccretionFact: View {
	let label: String
	let value: String

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(verbatim: label.uppercased())
				.font(.accretionMono(10.5, weight: .regular))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: value.isEmpty ? "–" : value)
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(AccretionTheme.fg)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 11)
		.padding(.horizontal, 13)
		.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}
}

/// Wraps its children onto new lines like the store's `flex-wrap` button rows.
struct AccretionFlow: Layout {
	var spacing: CGFloat = 8

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = _rows(width: proposal.width ?? .infinity, subviews: subviews)
		let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
		let width = rows.map(\.width).max() ?? 0
		return CGSize(width: proposal.width ?? width, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in _rows(width: bounds.width, subviews: subviews) {
			var x = bounds.minX
			for index in row.items {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + spacing
		}
	}

	private struct _Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

	private func _rows(width: CGFloat, subviews: Subviews) -> [_Row] {
		var rows = [_Row()]
		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
			if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
				rows.append(_Row())
			}
			let added = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
			rows[rows.count - 1].items.append(index)
			rows[rows.count - 1].width += added
			rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
		}
		return rows
	}
}

/// The store's `.back` button and an interactive swipe-back that still works with the
/// navigation bar hidden.
struct AccretionBackButton: View {
	@Environment(\.dismiss) private var _dismiss

	var body: some View {
		Button { _dismiss() } label: { Text(verbatim: "← " + String.localized("Back")) }
			.buttonStyle(AccretionButtonStyle(prominent: false))
	}
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
	override open func viewDidLoad() {
		super.viewDidLoad()
		interactivePopGestureRecognizer?.delegate = self
	}

	public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
		// not mid-transition: swiping during a push is what freezes or corrupts a stack
		viewControllers.count > 1 && transitionCoordinator == nil
	}
}

/// "Nothing here yet" for iOS 16, which has no ContentUnavailableView (those screens were blank)
struct AccretionEmptyState<Actions: View>: View {
	let title: String
	let message: String
	let systemImage: String
	@ViewBuilder var actions: Actions

	var body: some View {
		VStack(spacing: 10) {
			Image(systemName: systemImage)
				.font(.system(size: 40))
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: title)
				.font(.accretionDisplay(20))
				.foregroundStyle(AccretionTheme.fg)
			Text(verbatim: message)
				.font(.system(size: 15))
				.foregroundStyle(AccretionTheme.muted)
				.multilineTextAlignment(.center)
			actions.padding(.top, 4)
		}
		.padding(32)
		.frame(maxWidth: .infinity)
	}
}

/// The store's "live" dot, with a ring that pulses outward every 2.4 s like the website's .live
/// animation. Its colour carries meaning: green working, amber behind or needs attention, red down.
/// Still when Reduce Motion is on.
struct LiveDot: View {
	enum Tone {
		case good, warn, bad

		var color: Color {
			switch self {
			case .good: return AccretionTheme.good
			case .warn: return AccretionTheme.warn
			case .bad: return AccretionTheme.bad
			}
		}

		/// How fresh the store index is, from its "2026-10-11 13:12 UTC" build time: green within
		/// 8 hours (it rebuilds every 6), amber within a day, red after that
		static func freshness(_ updated: String?) -> Tone {
			guard let updated else { return .good }
			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.timeZone = TimeZone(identifier: "UTC")
			formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
			guard let date = formatter.date(from: updated) else { return .good }
			let age = -date.timeIntervalSinceNow
			return age < 8 * 3600 ? .good : age < 24 * 3600 ? .warn : .bad
		}
	}

	var tone: Tone = .good
	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@State private var _pulse = false

	var body: some View {
		Circle()
			.fill(tone.color)
			.frame(width: 8, height: 8)
			.background {
				if !_reduceMotion {
					Circle()
						.fill(tone.color.opacity(_pulse ? 0 : 0.55))
						.frame(width: 8, height: 8)
						.scaleEffect(_pulse ? 3.2 : 1)
				}
			}
			.onAppear {
				guard !_reduceMotion else { return }
				withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) { _pulse = true }
			}
			.accessibilityHidden(true)
	}
}

/// The website's grid (body's two 1px linear-gradients, background-size 28px): a 1-pt line every
/// 28 pt across and down, drawn as vectors at the screen's full resolution so it stays as sharp as
/// the site's. Lines cross like the site's two layers, so crossings are a touch brighter. The
/// drawing is one path that only redraws when the size or appearance changes.
struct AccretionGrid: View {
	@Environment(\.colorScheme) private var _colorScheme

	var body: some View {
		let dark = _colorScheme == .dark
		let hex = dark ? AccretionTokens.gridLineDark : AccretionTokens.gridLineLight
		let line = Color(
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255,
			opacity: Double(dark ? AccretionTokens.gridAlphaDark : AccretionTokens.gridAlphaLight)
		)
		Canvas { context, size in
			let step = AccretionTokens.gridSize
			var path = Path()
			var x: CGFloat = 0
			while x < size.width {
				path.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
				x += step
			}
			var y: CGFloat = 0
			while y < size.height {
				path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
				y += step
			}
			context.fill(path, with: .color(line))
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}

/// The page background's slow-moving light, drawn exactly like the website's `body::before`: a box
/// 20vmax larger than the screen on every side, a violet glow at 30% 25% of it and a cyan one at
/// 75% 70%, each fading out at 70% of its 42vmax / 36vmax radius, drifting on the 40-second
/// `drift` keyframes (alternating, ease-in-out). Drawn at 15 frames a second, and still with
/// Reduce Motion or Low Power Mode on, so it costs next to nothing.
struct AccretionAmbientGlow: View {
	@Environment(\.accessibilityReduceMotion) private var _reduceMotion
	@Environment(\.colorScheme) private var _colorScheme
	@State private var _lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

	var body: some View {
		let still = _reduceMotion || _lowPower
		TimelineView(.animation(minimumInterval: 1.0 / 15, paused: still)) { context in
			Canvas { canvas, size in
				let vmax = max(size.width, size.height)
				let drift = still ? .zero : Self._drift(at: context.date.timeIntervalSinceReferenceDate, vmax: vmax)
				// inset: -20vmax
				let box = CGRect(origin: .zero, size: size).insetBy(dx: -0.2 * vmax, dy: -0.2 * vmax).offsetBy(dx: drift.x, dy: drift.y)
				let strength = _colorScheme == .dark ? AccretionTokens.glow.dark : AccretionTokens.glow.light // --glow
				_glow(
					in: &canvas,
					center: CGPoint(x: box.minX + box.width * 0.30, y: box.minY + box.height * 0.25),
					radius: 0.42 * vmax * 0.7,
					color: AccretionTheme.accent.opacity(strength)
				)
				_glow(
					in: &canvas,
					center: CGPoint(x: box.minX + box.width * 0.75, y: box.minY + box.height * 0.70),
					radius: 0.36 * vmax * 0.7,
					color: AccretionTheme.accent2.opacity(strength * 0.7)
				)
			}
		}
		.allowsHitTesting(false)
		.accessibilityHidden(true)
		.onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
			_lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
		}
	}

	/// `@keyframes drift`: 0% (0, 0), 50% (6vmax, -4vmax), 100% (-5vmax, 5vmax), 40 s each way,
	/// alternating, eased in and out between keyframes like CSS's ease-in-out
	private static func _drift(at time: TimeInterval, vmax: CGFloat) -> CGPoint {
		let cycle = time.truncatingRemainder(dividingBy: 80)
		let progress = cycle <= 40 ? cycle / 40 : (80 - cycle) / 40
		let ease = { (x: Double) in (1 - cos(Double.pi * x)) / 2 }
		let a = CGPoint.zero, b = CGPoint(x: 6, y: -4), c = CGPoint(x: -5, y: 5)
		let (from, to, k) = progress <= 0.5 ? (a, b, ease(progress * 2)) : (b, c, ease(progress * 2 - 1))
		return CGPoint(x: (from.x + (to.x - from.x) * k) / 100 * vmax, y: (from.y + (to.y - from.y) * k) / 100 * vmax)
	}

	private func _glow(in canvas: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
		let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
		canvas.fill(
			Path(ellipseIn: rect),
			with: .radialGradient(
				Gradient(colors: [color, color.opacity(0)]),
				center: center,
				startRadius: 0,
				endRadius: radius
			)
		)
	}
}
