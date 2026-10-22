//
//  DiscoverView.swift
//  Accretion
//

import SwiftUI
import UIKit
import Nuke
import NukeUI

// MARK: - Discover
/// The Accretion store inside the app, a copy of getaccretion.app's home page: the top bar
/// (logo, Sign in, Add source, search, nav), hero with stats, the same shelves, and All apps with
/// category chips, the iOS filter and the Sort menu.
struct DiscoverView: View {
	@ObservedObject private var _store = StoreService.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@Environment(\.openURL) private var _openURL
	@AppStorage("accretion.discover.onlyFitting") private var _onlyFitting = true
	@AppStorage("accretion.discover.sort") private var _sort: StoreService.Sort = .updated
	@State private var _query = ""
	/// What the list searches for: the typed text once typing pauses (150 ms, like the website)
	@State private var _search = ""
	@State private var _category: String?
	@State private var _shown = 60
	@State private var _isSigningIn = false
	@State private var _isAddingSource = false
	@State private var _unread = 0
	@State private var _avatar: (letter: String, color: String)?
	/// Most liked, Top rated, Most discussed (the website's community shelves)
	@State private var _community: [StoreService.Shelf] = []
	@State private var _path = NavigationPath()
	@Namespace private var _zoom // Accretion: app icons grow into their page
	@FocusState private var _searchFocused: Bool

	private var _isBrowsing: Bool { !_search.isEmpty || _category != nil }

	var body: some View {
		NavigationStack(path: $_path) {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 0) {
					if _store.index == nil {
						_placeholder()
					} else {
						if !_isBrowsing {
							_hero()
							WhatsNewSection()
								.padding(.bottom, 18)
							// the website's order: store shelves, the community ones, then Utilities
							let shelves = _store.shelves(onlyFitting: _onlyFitting)
							ForEach(shelves.filter { $0.id != "utilities" } + _community + shelves.filter { $0.id == "utilities" }) { shelf in
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
			.refreshable {
				await _store.load(force: true)
				await WhatsNewFeed.shared.load(force: true)
				AccretionHaptics.refreshed()
			}
			.navigationDestination(for: StoreApp.self) { StoreAppView(app: $0).accretionZoomDestination($0.i, in: _zoom) }
			.navigationDestination(for: StoreListRoute.self) { StoreListView(route: $0) }
			.navigationDestination(for: SignGuideRoute.self) { _ in SignGuideView() }
			.navigationDestination(for: StatusRoute.self) { _ in StatusView() }
			.navigationDestination(for: CommunityFeedRoute.self) { CommunityFeedView(whatsNew: $0.whatsNew) }
			.navigationDestination(for: NotificationsRoute.self) { _ in NotificationsView() }
			.environment(\.accretionZoom, _zoom)
			.navigationDestination(for: StoreSourcesRoute.self) { _ in StoreSourcesView() }
			.toolbar(.hidden, for: .navigationBar)
		}
		.tint(AccretionTheme.accent)
		.task {
			await _store.load()
			await WhatsNewFeed.shared.load()
			await _loadCommunity()
		}
		.task(id: _query) {
			if !_query.isEmpty { try? await Task.sleep(nanoseconds: 150_000_000) }
			guard !Task.isCancelled else { return }
			_search = _query.trimmingCharacters(in: .whitespaces)
			_shown = 60
		}
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
		.sheet(isPresented: $_isAddingSource) { SourcesAddView() }
	}

	private func _loadCommunity() async {
		let stats = await _account.allAppStats()
		guard !stats.isEmpty, let apps = _store.index?.apps else { return }
		let byID = Dictionary(apps.map { ($0.i, $0) }, uniquingKeysWith: { first, _ in first })
		let known = stats.filter { byID[$0.app] != nil }
		func shelf(_ id: String, _ title: String, _ note: String, _ rows: [(app: String, likes: Int, ratings: Int, average: Double, comments: Int)]) -> StoreService.Shelf? {
			let list = rows.prefix(20).compactMap { byID[$0.app] }
			return list.isEmpty ? nil : StoreService.Shelf(id: id, title: title, note: note, apps: list, ranked: true)
		}
		_community = [
			shelf("liked", String.localized("Most liked"), String.localized("by the community"), known.filter { $0.likes > 0 }.sorted { $0.likes > $1.likes }),
			shelf("rated", String.localized("Top rated"), String.localized("3+ ratings"), known.filter { $0.ratings >= 3 }.sorted { ($0.average, $0.ratings) > ($1.average, $1.ratings) }),
			shelf("discussed", String.localized("Most discussed"), String.localized("comments"), known.filter { $0.comments > 0 }.sorted { $0.comments > $1.comments }),
		].compactMap { $0 }
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
					.accessibilityHidden(true) // the logo; the name next to it says it
					Text(verbatim: "Accretion")
						.font(.accretionDisplay(17))
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
						.fixedSize()
				}
				.accessibilityElement(children: .combine)
				.accessibilityAddTraits(.isHeader)
				Spacer(minLength: 0)
				if _account.isSignedIn {
					// the website's bell: unread likes, replies and follows
					Button {
						_unread = 0
						_path.append(NotificationsRoute())
					} label: {
						Image(systemName: "bell")
							.accretionFont(17, weight: .semibold)
							.foregroundStyle(AccretionTheme.fg)
							.frame(width: 36, height: 36)
							.accretionHitArea(4)
							.overlay(alignment: .topTrailing) {
								if _unread > 0 {
									Text(verbatim: _unread > 9 ? "9+" : "\(_unread)")
										.accretionFont(10, weight: .bold)
										.foregroundStyle(Color.white)
										.padding(.horizontal, 4)
										.frame(minWidth: 16, minHeight: 16)
										.background(AccretionTheme.roseFill, in: Capsule())
								}
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel(String.localized("Notifications"))
					.task(id: _account.email) {
						// every minute while Discover is showing, like the website
						while !Task.isCancelled {
							_unread = await _account.unreadNotifications()
							try? await Task.sleep(nanoseconds: 60_000_000_000)
						}
					}
				}
				// the website's account spot: your avatar when signed in, Sign in otherwise
				if _account.isSignedIn {
					Button { _isSigningIn = true } label: {
						StoreAvatar(letter: _avatar?.letter ?? "", hex: _avatar?.color ?? "8B5CF6", size: 32)
							.accretionHitArea(6)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(String.localized("Account"))
					.task(id: _account.email) { _avatar = await _account.myAvatar() }
				} else {
					Button(String.localized("Sign in")) { _isSigningIn = true }
						.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
				}
				Button(String.localized("Add source")) { _isAddingSource = true }
					.buttonStyle(AccretionButtonStyle())
					.fixedSize()
			}
			_searchField()
			_nav()
		}
		.padding(.horizontal, 16)
		.padding(.top, 10)
		.padding(.bottom, 10)
		.background {
			// the store background, up under the clock, over a blur like the website's header
			// (backdrop-filter): without it the rows scrolling under the bar show through faintly.
			// The material alone turns grey over the dark page, so the colour stays on top.
			AccretionTheme.bg.opacity(0.96)
				.background(.ultraThinMaterial)
				.ignoresSafeArea(edges: .top)
		}
		.overlay(alignment: .bottom) { AccretionTheme.line.frame(height: 1) }
	}

	private func _searchField() -> some View {
		HStack(spacing: 12) {
			HStack(spacing: 8) {
				Image(systemName: "magnifyingglass")
					.accretionFont(15)
					.foregroundStyle(AccretionTheme.muted)
					.accessibilityHidden(true)
				TextField(String.localized("Search apps, developers, bundle IDs"), text: $_query)
					.accretionFont(15)
					.focused($_searchFocused)
					.submitLabel(.search)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.foregroundStyle(AccretionTheme.fg)
					.padding(.vertical, 10)
				if !_query.isEmpty {
					Button { _query = "" } label: { Image(systemName: "xmark.circle.fill") }
						.foregroundStyle(AccretionTheme.muted)
						.accretionHitArea(12)
						.accessibilityLabel(String.localized("Clear search"))
				}
			}
			.padding(.horizontal, 12)
			.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
			// the system search field's Cancel: leaves search and puts the keyboard away
			if _searchFocused {
				Button(String.localized("Cancel")) {
					_query = ""
					_searchFocused = false
				}
				.accretionFont(15, weight: .semibold)
				.foregroundStyle(AccretionTheme.accentText)
				.accretionHitArea(10)
				.transition(.move(edge: .trailing).combined(with: .opacity))
			}
		}
		.animation(.easeOut(duration: 0.2), value: _searchFocused)
	}

	/// Discover · Sources · Feed · Saved · ♥, spread across the width like the web store on a phone
	private func _nav() -> some View {
		HStack(spacing: 4) {
			_navItem(String.localized("Discover"), on: !_isBrowsing) { _query = ""; _category = nil }
			_navItem(String.localized("Sources")) { _path.append(StoreSourcesRoute()) }
			_navItem(String.localized("Feed")) { _path.append(CommunityFeedRoute()) }
			_navItem(String.localized("Saved"), badge: _savedBadge.text, hot: _savedBadge.hot) {
				_path.append(StoreListRoute(title: String.localized("Saved"), saved: true))
			}
			Button { _openURL(URL(string: "https://getaccretion.app/#/support")!) } label: {
				Text(verbatim: "♥")
					.accretionFont(14, weight: .semibold)
					.foregroundStyle(AccretionTheme.rose)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 8)
					.accretionHitArea(6, .vertical)
			}
			.buttonStyle(.plain)
			.accessibilityLabel(String.localized("Support Accretion"))
		}
	}

	/// "3", or "2 new" in green when saved apps have updates, like the website's Saved pill
	private var _savedBadge: (text: String?, hot: Bool) {
		let summary = _store.savedSummary()
		if summary.updates > 0 { return (String.localized("%@ new", arguments: String(summary.updates)), true) }
		return (summary.count > 0 ? String(summary.count) : nil, false)
	}

	private func _navItem(_ title: String, on: Bool = false, badge: String? = nil, hot: Bool = false, action: @escaping () -> Void) -> some View {
		Button {
			AccretionHaptics.select()
			withAnimation(.easeOut(duration: 0.2)) { action() }
		} label: {
			HStack(spacing: 6) {
				Text(verbatim: title)
				if let badge {
					Text(verbatim: badge)
						.font(.accretionMono(11))
						.foregroundStyle(hot ? AccretionTheme.good : AccretionTheme.muted)
						.padding(.horizontal, 6)
						.padding(.vertical, 1)
						.background(hot ? AccretionTheme.good.opacity(0.2) : AccretionTheme.raised, in: Capsule())
						.overlay(Capsule().stroke(hot ? Color.clear : AccretionTheme.line, lineWidth: 1))
				}
			}
			.accretionFont(14, weight: .semibold)
			.lineLimit(1)
			.minimumScaleFactor(0.85)
			.foregroundStyle(on ? AccretionTheme.fg : AccretionTheme.muted)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
			.background(on ? AccretionTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			.accretionHitArea(6, .vertical)
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
				LiveDot(tone: .freshness(stats?.updated))
				Text(verbatim: (String.localized("Live index") + " · " + (stats?.updated.map { String.localized("built %@", arguments: $0) } ?? String.localized("live"))).uppercased())
					.font(.accretionMono(12, weight: .regular))
					.tracking(1)
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
			.padding(.bottom, 10)
			// the website balances the two lines (text-wrap: balance): "Every source, / pulled into one."
			Text(verbatim: String.localized("Every source,") + "\n" + String.localized("pulled into one."))
				.font(.accretionDisplay(28)) // h1 on a phone: clamp(28px, 4.6vw, 46px)
				.foregroundStyle(AccretionTheme.headline)
				.fixedSize(horizontal: false, vertical: true)
				.padding(.bottom, 12)
			(Text(verbatim: String.localized("Apps from") + " ")
			 + Text(verbatim: (stats?.sources ?? index?.sources.count ?? 0).formatted()).bold().foregroundColor(AccretionTheme.fg)
			 + Text(verbatim: " " + String.localized("public AltStore and SideStore sources, merged and cleaned. One entry per app, always the newest version.")))
				.accretionFont(15) // .lede: the page's 15px body text
				.foregroundStyle(AccretionTheme.muted)
				.fixedSize(horizontal: false, vertical: true)
			NavigationLink(value: SignGuideRoute()) {
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
			NavigationLink(value: StatusRoute()) {
				Text(verbatim: String.localized("Store status →"))
					.accretionFont(13, weight: .semibold)
					.foregroundStyle(AccretionTheme.link)
					.accretionHitArea(14)
			}
			.buttonStyle(.plain)
			.padding(.top, 10)
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
		let apps = _store.apps(matching: _search, category: _category, onlyFitting: _onlyFitting, sort: _sort)
		VStack(alignment: .leading, spacing: 0) {
			Text(verbatim: _search.isEmpty
				? (_category.flatMap { StoreService.categoryNames[$0] } ?? String.localized("All apps"))
				: String.localized("Results for “%@”", arguments: _search))
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
						.accretionFont(13, weight: .semibold)
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
						Image(systemName: "chevron.up.chevron.down").accretionFont(11)
					}
					.accretionFont(15)
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
						.buttonStyle(AccretionPressStyle())
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
		Button {
			AccretionHaptics.select()
			withAnimation(.easeOut(duration: 0.2)) { action() }
		} label: {
			HStack(spacing: 6) {
				Text(verbatim: title).accretionFont(13, weight: .medium)
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
		.buttonStyle(AccretionPressStyle())
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
			AccretionDiscoverSkeleton()
		}
	}
}

// MARK: - Avatar (.avatar)
/// The website's avatar: a lit circle in the profile colour with the name's first letter
struct StoreAvatar: View {
	let letter: String
	let hex: String
	var size: CGFloat = 36

	/// The profile colour mixed toward white (target 1) or black (target 0) by `amount`
	private func _shade(toward target: Double, by amount: Double) -> Color {
		let value = UInt32(hex, radix: 16) ?? 0x8B5CF6
		func mix(_ channel: UInt32) -> Double {
			let c = Double(channel & 0xFF) / 255
			return c + (target - c) * amount
		}
		return Color(red: mix(value >> 16), green: mix(value >> 8), blue: mix(value))
	}

	var body: some View {
		Circle()
			.fill(RadialGradient(
				colors: [_shade(toward: 1, by: 0.25), _shade(toward: 1, by: 0), _shade(toward: 0, by: 0.2)],
				center: UnitPoint(x: 0.3, y: 0.25),
				startRadius: 0,
				endRadius: size * 0.75
			))
			.frame(width: size, height: size)
			.overlay {
				Text(verbatim: letter)
					.font(.accretionDisplay(size * 0.42))
					.foregroundStyle(AccretionTheme.avatarInk)
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
							.accretionFont(14, weight: .semibold)
							.foregroundStyle(AccretionTheme.link)
							.accretionHitArea(13)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(String.localized("See all %@", arguments: shelf.title))
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
				.buttonStyle(AccretionPressStyle())
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

	/// List and card icons (up to 64 pt) share one size, so one decoded copy serves them all
	static func processors(for size: CGFloat) -> [any ImageProcessing] {
		[ImageProcessors.Resize(width: size > 64 ? 96 : 64)]
	}

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: radius ?? size * 0.2333, style: .continuous)
		LazyImage(url: url) { state in
			if let image = state.image {
				image.resizable().scaledToFill()
			} else {
				AccretionTheme.raised
			}
		}
		// Accretion: decoded at icon size, not full size (smoother scrolling); the opening
		// loads the first icons with the same processors (AccretionWarmUp) so they are ready
		.processors(Self.processors(for: size))
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
				.accretionZoomSource(app.i)
			HStack(spacing: 4) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: app.n)
						.accretionFont(15, weight: .semibold)
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
					HStack(spacing: 6) {
						if _store.isMod(app) { AccretionBadge(text: app.isTweak ? "Accretion Tweak" : "Accretion Mod", color: AccretionTheme.accentText) }
						Text(verbatim: StoreFormat.meta(app))
							.font(.accretionMono(12, weight: .regular))
							.foregroundStyle(AccretionTheme.muted)
							.lineLimit(1)
					}
				}
				Spacer(minLength: 0)
				Text(verbatim: "›")
					.accretionFont(22)
					.foregroundStyle(AccretionTheme.muted)
					.accessibilityHidden(true)
			}
			.frame(maxHeight: .infinity)
			.overlay(alignment: .top) { if divider { AccretionTheme.line.frame(height: 1) } }
		}
		.frame(height: 64)
		.contentShape(Rectangle())
		.prefetchesDetail(app)
	}
}

extension View {
	/// Loads the app's page details once its row has stayed on screen for a moment
	/// (a fast scroll past it loads nothing), so tapping it zooms into a finished page
	func prefetchesDetail(_ app: StoreApp) -> some View {
		task(id: app.i) {
			try? await Task.sleep(nanoseconds: 300_000_000)
			guard !Task.isCancelled else { return }
			StoreService.shared.prefetchDetail(for: app)
		}
	}
}

/// All-apps card (.card): icon, name with badges, developer, version (cyan) · date · size
struct StoreAppCard: View {
	@ObservedObject private var _store = StoreService.shared
	let app: StoreApp

	var body: some View {
		HStack(spacing: 13) {
			StoreAppIcon(url: app.iconURL, size: 60, radius: 14)
				.accretionZoomSource(app.i)
			VStack(alignment: .leading, spacing: 0) {
				HStack(spacing: 7) {
					Text(verbatim: app.n)
						.accretionFont(15, weight: .semibold)
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
					if _store.isMod(app) { AccretionBadge(text: app.isTweak ? "Accretion Tweak" : "Accretion Mod", color: AccretionTheme.accentText) }
					if _store.hasUpdate(app) {
						AccretionBadge(text: "update", color: AccretionTheme.link)
					} else if _store.isNew(app) {
						AccretionBadge(text: "new")
					}
				}
				Text(verbatim: app.d)
					.accretionFont(13)
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(1)
				HStack(spacing: 8) {
					Text(verbatim: "v\(app.v)").foregroundStyle(AccretionTheme.link)
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
		.prefetchesDetail(app)
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
