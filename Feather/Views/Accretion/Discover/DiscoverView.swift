//
//  DiscoverView.swift
//  Accretion
//

import SwiftUI
import UIKit
import NukeUI

// MARK: - Discover
/// The Accretion store inside the app, a copy of getaccretion.github.io's home page: the top bar
/// (logo, Sign in, Add source, search, nav), hero with stats, the same shelves, and All apps with
/// category chips, the iOS filter and the Sort menu.
struct DiscoverView: View {
	@ObservedObject private var _store = StoreService.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@Environment(\.openURL) private var _openURL
	@AppStorage("accretion.discover.onlyFitting") private var _onlyFitting = true
	@AppStorage("accretion.discover.sort") private var _sort: StoreService.Sort = .updated
	@State private var _query = ""
	@State private var _category: String?
	@State private var _shown = 60
	@State private var _isSigningIn = false
	@State private var _isAddingSource = false
	@State private var _path = NavigationPath()

	private var _isBrowsing: Bool { !_query.isEmpty || _category != nil }

	var body: some View {
		NavigationStack(path: $_path) {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					if _store.index == nil {
						_placeholder()
					} else {
						if !_isBrowsing {
							_hero()
							ForEach(_store.shelves(onlyFitting: _onlyFitting)) { shelf in
								StoreShelfView(shelf: shelf)
									.padding(.top, 8)
									.padding(.bottom, 18)
							}
						}
						_all()
					}
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 40)
			}
			.scrollDismissesKeyboard(.immediately)
			// the sticky bar sits outside the scroll view, so content scrolls under it and never
			// shows through the status bar
			.safeAreaInset(edge: .top, spacing: 0) { _topBar() }
			.accretionBackground()
			.refreshable { await _store.load(force: true) }
			.navigationDestination(for: StoreApp.self) { StoreAppView(app: $0) }
			.navigationDestination(for: StoreListRoute.self) { StoreListView(route: $0) }
			.toolbar(.hidden, for: .navigationBar)
		}
		.tint(AccretionTheme.accent)
		.task { await _store.load() }
		.sheet(isPresented: $_isSigningIn) { NavigationStack { AccretionAccountView() } }
		.sheet(isPresented: $_isAddingSource) { SourcesAddView() }
	}

	// MARK: Top bar (.top): logo, Sign in, Add source, search, nav
	private func _topBar() -> some View {
		VStack(spacing: 10) {
			HStack(spacing: 12) {
				HStack(spacing: 9) {
					LazyImage(url: StoreService.base.appendingPathComponent("icon-192.png")) { state in
						if let image = state.image { image.resizable() } else { AccretionTheme.raised }
					}
					.frame(width: 30, height: 30)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
					Text(verbatim: "Accretion")
						.font(.accretionDisplay(17))
						.foregroundStyle(AccretionTheme.fg)
				}
				Spacer(minLength: 0)
				Button(_account.isSignedIn ? String.localized("Account") : String.localized("Sign in")) { _isSigningIn = true }
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
				Button(String.localized("Add source")) { _isAddingSource = true }
					.buttonStyle(AccretionButtonStyle())
			}
			_searchField()
			_nav()
		}
		.padding(.horizontal, 16)
		.padding(.top, 10)
		.padding(.bottom, 10)
		.background {
			// solid store background (a material turns grey over the dark page), up under the clock
			AccretionTheme.bg.opacity(0.96).ignoresSafeArea(edges: .top)
		}
		.overlay(alignment: .bottom) { AccretionTheme.line.frame(height: 1) }
	}

	private func _searchField() -> some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 15))
				.foregroundStyle(AccretionTheme.muted)
			TextField(String.localized("Search apps, developers, IDs"), text: $_query)
				.font(.system(size: 15))
				.submitLabel(.search)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.foregroundStyle(AccretionTheme.fg)
				.padding(.vertical, 10)
			if !_query.isEmpty {
				Button { _query = "" } label: { Image(systemName: "xmark.circle.fill") }
					.foregroundStyle(AccretionTheme.muted)
					.accessibilityLabel(String.localized("Clear search"))
			}
		}
		.padding(.horizontal, 12)
		.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}

	/// Discover · Saved · Feed · ♥, spread across the width like the web store on a phone
	private func _nav() -> some View {
		HStack(spacing: 4) {
			_navItem(String.localized("Discover"), on: !_isBrowsing) { _query = ""; _category = nil }
			_navItem(String.localized("Saved"), badge: _store.saved.isEmpty ? nil : _store.saved.count) {
				_path.append(StoreListRoute(title: String.localized("Saved"), saved: true))
			}
			_navItem(String.localized("Feed")) { _openURL(URL(string: "https://getaccretion.github.io/#/feed")!) }
			Button { _openURL(URL(string: "https://getaccretion.github.io/#/support")!) } label: {
				Text(verbatim: "♥")
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(Color(red: 244.0 / 255, green: 63.0 / 255, blue: 94.0 / 255))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
			}
			.buttonStyle(.plain)
			.accessibilityLabel(String.localized("Support Accretion"))
		}
	}

	private func _navItem(_ title: String, on: Bool = false, badge: Int? = nil, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 6) {
				Text(verbatim: title)
				if let badge {
					Text(verbatim: "\(badge)")
						.font(.accretionMono(11))
						.padding(.horizontal, 6)
						.padding(.vertical, 1)
						.background(AccretionTheme.raised, in: Capsule())
						.overlay(Capsule().stroke(AccretionTheme.line, lineWidth: 1))
				}
			}
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(on ? AccretionTheme.fg : AccretionTheme.muted)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
			.background(on ? AccretionTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
		}
		.buttonStyle(.plain)
	}

	// MARK: Hero (.hero): eyebrow, headline, lede, Sign your own apps, stats
	@ViewBuilder
	private func _hero() -> some View {
		let index = _store.index
		let stats = _store.stats
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 8) {
				Circle().fill(AccretionTheme.good).frame(width: 8, height: 8)
				Text(verbatim: (String.localized("Live index") + " · " + (stats?.updated.map { String.localized("built %@", arguments: $0) } ?? String.localized("live"))).uppercased())
					.font(.accretionMono(12, weight: .regular))
					.tracking(1)
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
			.padding(.bottom, 10)
			Text(verbatim: String.localized("Every source, pulled into one."))
				.font(.accretionDisplay(30))
				.foregroundStyle(AccretionTheme.headline)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.bottom, 12)
			(Text(verbatim: String.localized("Apps from") + " ")
			 + Text(verbatim: (stats?.sources ?? index?.sources.count ?? 0).formatted()).bold().foregroundColor(AccretionTheme.fg)
			 + Text(verbatim: " " + String.localized("public AltStore and SideStore sources, merged and cleaned. One entry per app, always the newest version.")))
				.foregroundStyle(AccretionTheme.muted)
				.fixedSize(horizontal: false, vertical: true)
			Button { _openURL(URL(string: "https://getaccretion.github.io/#/sign")!) } label: {
				Text(verbatim: "✍️ " + String.localized("Sign your own apps"))
			}
			.buttonStyle(AccretionButtonStyle(prominent: false))
			.padding(.top, 14)

			Grid(horizontalSpacing: 10, verticalSpacing: 10) {
				GridRow {
					_stat(String.localized("apps"), stats?.apps ?? index?.apps.count)
					_stat(String.localized("sources"), stats?.sources ?? index?.sources.count)
				}
				GridRow {
					_stat(String.localized("updated 7d"), stats?.updated_7d)
					_stat(String.localized("new 30d"), stats?.new_30d ?? index?.apps.filter(_store.isNew).count)
				}
			}
			.padding(.top, 24)
		}
		.padding(.top, 34)
		.padding(.bottom, 22)
	}

	private func _stat(_ label: String, _ value: Int?) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: label.uppercased())
				.font(.accretionMono(11, weight: .regular))
				.tracking(1.1)
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: value.map { $0.formatted() } ?? "–")
				.font(.accretionDisplay(26))
				.foregroundStyle(AccretionTheme.headline)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 12)
		.padding(.horizontal, 14)
		.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}

	// MARK: All apps (.all): title, count, chips, iOS filter, sort, cards
	@ViewBuilder
	private func _all() -> some View {
		let apps = _store.apps(matching: _query, category: _category, onlyFitting: _onlyFitting, sort: _sort)
		VStack(alignment: .leading, spacing: 0) {
			Text(verbatim: _query.isEmpty
				? (_category.flatMap { StoreService.categoryNames[$0] } ?? String.localized("All apps"))
				: String.localized("Results for “%@”", arguments: _query))
				.font(.accretionDisplay(20))
				.foregroundStyle(AccretionTheme.fg)
				.padding(.top, _isBrowsing ? 18 : 0)
			_chips().padding(.top, 8)
			HStack(spacing: 10) {
				Spacer(minLength: 0)
				Button {
					_onlyFitting.toggle()
					_shown = 60
				} label: {
					Text(verbatim: _onlyFitting
						? String.localized("Works on iOS %@ ✓", arguments: UIDevice.current.systemVersion)
						: String.localized("Show only apps for iOS %@", arguments: UIDevice.current.systemVersion))
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(_onlyFitting ? AccretionTheme.good : AccretionTheme.muted)
						.padding(.horizontal, 12)
						.padding(.vertical, 9)
						.background(_onlyFitting ? AccretionTheme.good.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(_onlyFitting ? AccretionTheme.good.opacity(0.45) : AccretionTheme.line, lineWidth: 1))
				}
				.buttonStyle(.plain)
				Menu {
					Picker(String.localized("Sort"), selection: $_sort) {
						ForEach(StoreService.Sort.allCases) { Text(verbatim: $0.title).tag($0) }
					}
					.pickerStyle(.inline)
				} label: {
					HStack(spacing: 6) {
						Text(verbatim: _sort.title)
						Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
					}
					.font(.system(size: 15))
					.foregroundStyle(AccretionTheme.fg)
					.padding(.horizontal, 10)
					.padding(.vertical, 9)
					.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
					.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
				}
			}
			.padding(.top, 10)
			Text(verbatim: String.localized("%@ apps", arguments: apps.count.formatted()))
				.font(.accretionMono(12, weight: .regular))
				.foregroundStyle(AccretionTheme.muted)
				.padding(.top, 16)
				.padding(.bottom, 12)

			LazyVStack(spacing: 12) {
				ForEach(apps.prefix(_shown)) { app in
					NavigationLink(value: app) { StoreAppCard(app: app) }
						.buttonStyle(.plain)
				}
			}
			if apps.count > _shown {
				Button(String.localized("Show more")) { _shown += 60 }
					.buttonStyle(AccretionButtonStyle(prominent: false))
					.frame(maxWidth: .infinity)
					.padding(.top, 18)
			} else if apps.isEmpty {
				Text(verbatim: String.localized("Nothing matches. Try other words, or turn off the iOS filter."))
					.font(.footnote)
					.foregroundStyle(AccretionTheme.muted)
			}
		}
	}

	/// Category chips with counts; the selected one is inverted (.chip[aria-selected=true])
	private func _chips() -> some View {
		let counts = _store.categoryCounts()
		let order = StoreService.categoryNames.keys
			.filter { counts[$0] != nil }
			.sorted { ($0 == "other" ? 1 : 0, -(counts[$0] ?? 0)) < ($1 == "other" ? 1 : 0, -(counts[$1] ?? 0)) }
		return ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				_chip(String.localized("All"), count: _store.index?.apps.count ?? 0, selected: _category == nil) { _category = nil; _shown = 60 }
				ForEach(order, id: \.self) { id in
					_chip(String.localized(StoreService.categoryNames[id] ?? id), count: counts[id] ?? 0, selected: _category == id) {
						_category = id
						_shown = 60
					}
				}
			}
			.padding(.bottom, 4)
		}
	}

	private func _chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			HStack(spacing: 6) {
				Text(verbatim: title).font(.system(size: 13, weight: .medium))
				Text(verbatim: count.formatted())
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(selected ? AccretionTheme.bg.opacity(0.7) : AccretionTheme.muted)
			}
			.padding(.horizontal, 13)
			.padding(.vertical, 7)
			.foregroundStyle(selected ? AccretionTheme.bg : AccretionTheme.fg)
			.background(selected ? AccretionTheme.fg : AccretionTheme.surface, in: Capsule())
			.overlay(Capsule().stroke(selected ? AccretionTheme.fg : AccretionTheme.line, lineWidth: 1))
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	@ViewBuilder
	private func _placeholder() -> some View {
		if _store.loadFailed {
			VStack(spacing: 12) {
				Text(verbatim: String.localized("Couldn't load the store. Check your connection."))
					.foregroundStyle(AccretionTheme.muted)
				Button(String.localized("Try Again")) { Task { await _store.load(force: true) } }
					.buttonStyle(AccretionButtonStyle())
			}
			.frame(maxWidth: .infinity)
			.padding(.top, 40)
		} else {
			ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
		}
	}
}

// MARK: - Shelf (.shelf)
/// A titled shelf: pages of five rows, swiped sideways, with "See all" when there's more.
struct StoreShelfView: View {
	let shelf: StoreService.Shelf
	private static let perPage = 5

	/// Start indexes of each page of five
	private var _pages: [Int] { Array(stride(from: 0, to: shelf.apps.count, by: Self.perPage)) }

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline, spacing: 12) {
				(Text(verbatim: shelf.title).font(.accretionDisplay(20)).foregroundColor(AccretionTheme.fg)
				 + Text(verbatim: shelf.note.map { "  " + $0 } ?? "").font(.accretionMono(12, weight: .regular)).foregroundColor(AccretionTheme.muted))
				Spacer(minLength: 0)
				if let seeAll = shelf.seeAll {
					NavigationLink(value: seeAll) {
						Text(verbatim: String.localized("See all"))
							.font(.system(size: 14, weight: .semibold))
							.foregroundStyle(AccretionTheme.accent2)
					}
					.buttonStyle(.plain)
				}
			}
			if _pages.count > 1 {
				GeometryReader { geo in
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(alignment: .top, spacing: 18) {
							ForEach(_pages, id: \.self) { start in
								_page(start).frame(width: geo.size.width * 0.88)
							}
						}
						.modifier(_SnapTargets())
					}
					.modifier(_SnapPaging())
				}
				.frame(height: CGFloat(min(shelf.apps.count, Self.perPage)) * 64)
			} else {
				_page(0)
			}
		}
	}

	private func _page(_ start: Int) -> some View {
		VStack(spacing: 0) {
			ForEach(start..<min(start + Self.perPage, shelf.apps.count), id: \.self) { index in
				NavigationLink(value: shelf.apps[index]) {
					StoreAppRow(app: shelf.apps[index], rank: shelf.ranked ? index + 1 : nil, divider: index != start)
				}
				.buttonStyle(.plain)
			}
		}
	}
}

/// Shelves stop on a page instead of halfway (iOS 17+, like the web store's scroll snap)
private struct _SnapTargets: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 17.0, *) { content.scrollTargetLayout() } else { content }
	}
}

private struct _SnapPaging: ViewModifier {
	func body(content: Content) -> some View {
		if #available(iOS 17.0, *) { content.scrollTargetBehavior(.viewAligned) } else { content }
	}
}

// MARK: - Rows and cards
/// The store's app icon: rounded square on the raised colour while loading
struct StoreAppIcon: View {
	let url: URL?
	var size: CGFloat = 60
	var radius: CGFloat?

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: radius ?? size * 0.2333, style: .continuous)
		LazyImage(url: url) { state in
			if let image = state.image {
				image.resizable().scaledToFill()
			} else {
				AccretionTheme.raised
			}
		}
		.frame(width: size, height: size)
		.clipShape(shape)
		.overlay(shape.stroke(AccretionTheme.line, lineWidth: 1))
	}
}

/// Shelf row (.row): rank, icon, name, "v1.2 · Games · today", ›, with a hairline between rows
struct StoreAppRow: View {
	@ObservedObject private var _store = StoreService.shared
	let app: StoreApp
	var rank: Int?
	var divider = false

	var body: some View {
		HStack(spacing: 12) {
			if let rank {
				Text(verbatim: "\(rank)")
					.font(.accretionMono(15))
					.foregroundStyle(AccretionTheme.muted)
					.frame(width: 21)
			}
			StoreAppIcon(url: app.iconURL, size: 48, radius: 12)
			HStack(spacing: 4) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: app.n)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
					HStack(spacing: 6) {
						if _store.isMod(app) { AccretionBadge(text: "Accretion Mod", color: AccretionTheme.accent) }
						Text(verbatim: StoreFormat.meta(app))
							.font(.accretionMono(12, weight: .regular))
							.foregroundStyle(AccretionTheme.muted)
							.lineLimit(1)
					}
				}
				Spacer(minLength: 0)
				Text(verbatim: "›")
					.font(.system(size: 22))
					.foregroundStyle(AccretionTheme.muted)
			}
			.frame(maxHeight: .infinity)
			.overlay(alignment: .top) { if divider { AccretionTheme.line.frame(height: 1) } }
		}
		.frame(height: 64)
		.contentShape(Rectangle())
	}
}

/// All-apps card (.card): icon, name with badges, developer, version (cyan) · date · size
struct StoreAppCard: View {
	@ObservedObject private var _store = StoreService.shared
	let app: StoreApp

	var body: some View {
		HStack(spacing: 13) {
			StoreAppIcon(url: app.iconURL, size: 60, radius: 14)
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 7) {
					Text(verbatim: app.n)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
					if _store.isMod(app) { AccretionBadge(text: "Accretion Mod", color: AccretionTheme.accent) }
					if _store.hasUpdate(app) {
						AccretionBadge(text: "update", color: AccretionTheme.accent2)
					} else if _store.isNew(app) {
						AccretionBadge(text: "new")
					}
				}
				Text(verbatim: app.d)
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(1)
				HStack(spacing: 8) {
					Text(verbatim: "v\(app.v)").foregroundStyle(AccretionTheme.accent2)
					Text(verbatim: StoreFormat.since(app))
					if let size = app.z { Text(verbatim: StoreFormat.bytes(size)) }
				}
				.font(.accretionMono(11.5, weight: .regular))
				.foregroundStyle(AccretionTheme.muted)
				.lineLimit(1)
				.padding(.top, 3)
			}
			Spacer(minLength: 0)
		}
		.padding(13)
		.accretionCard()
	}
}

// MARK: - Formatting (same wording as the web store)
@MainActor
enum StoreFormat {
	static func since(_ app: StoreApp) -> String {
		guard app.u == nil else { return String.localized("date unknown") }
		return ago(app.t)
	}

	/// "today", "yesterday", "3d ago", "2mo ago", "1y ago" for a date or timestamp
	static func ago(_ text: String) -> String {
		let date = _timestamp(text) ?? StoreService.day(text)
		guard let date else { return text }
		let seconds = Date().timeIntervalSince(date)
		if text.count > 10, seconds < 86400 {
			// comments: minutes and hours, like the web feed
			if seconds < 60 { return String.localized("just now") }
			if seconds < 3600 { return String.localized("%@m ago", arguments: String(Int(seconds / 60))) }
			return String.localized("%@h ago", arguments: String(Int(seconds / 3600)))
		}
		let days = Int(seconds / 86400)
		switch days {
		case ..<1: return String.localized("today")
		case 1: return String.localized("yesterday")
		case 2..<30: return String.localized("%@d ago", arguments: String(days))
		case 30..<365: return String.localized("%@mo ago", arguments: String(days / 30))
		default: return String.localized("%@y ago", arguments: String(days / 365))
		}
	}

	private static func _timestamp(_ text: String) -> Date? {
		guard text.count > 10 else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: text) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		// drop fractional seconds the formatter can't read (Postgres writes six digits)
		let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
		return formatter.date(from: trimmed)
	}

	static func meta(_ app: StoreApp) -> String {
		["v\(app.v)", StoreService.categoryNames[app.c], since(app)].compactMap { $0 }.joined(separator: " · ")
	}

	static func bytes(_ size: Int) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
	}
}
