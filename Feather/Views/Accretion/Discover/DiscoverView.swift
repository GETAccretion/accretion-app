//
//  DiscoverView.swift
//  Accretion
//

import SwiftUI
import NukeUI

// MARK: - Discover
/// The Accretion store inside the app, built like getaccretion.github.io: hero, search,
/// category chips, the same shelves, and app pages with one-tap install.
struct DiscoverView: View {
	@ObservedObject private var _store = StoreService.shared
	@AppStorage("accretion.discover.onlyFitting") private var _onlyFitting = true
	@State private var _query = ""
	@State private var _category: String?
	@State private var _shown = 60

	private var _isBrowsing: Bool { !_query.isEmpty || _category != nil }

	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 22) {
					_hero()
					_searchField()
					_chips()

					if _store.index == nil {
						_placeholder()
					} else if _isBrowsing {
						_list()
					} else {
						ForEach(_store.shelves(onlyFitting: _onlyFitting)) { shelf in
							StoreShelfView(shelf: shelf)
						}
						_list()
					}
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 40)
			}
			.accretionBackground()
			.refreshable { await _store.load(force: true) }
			.navigationDestination(for: StoreApp.self) { app in
				StoreAppView(app: app)
			}
			.toolbar(.hidden, for: .navigationBar)
		}
		.tint(AccretionTheme.accent)
		.task { await _store.load() }
	}

	// MARK: Pieces
	@ViewBuilder
	private func _hero() -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				Circle().fill(AccretionTheme.good).frame(width: 7, height: 7)
				Text(verbatim: String.localized("LIVE INDEX"))
					.font(.accretionMono(11))
					.tracking(1)
					.foregroundStyle(AccretionTheme.muted)
			}
			Text(verbatim: String.localized("Every source,\npulled into one."))
				.font(.accretionDisplay(32, weight: .heavy))
				.foregroundStyle(AccretionTheme.fg)
			if let index = _store.index {
				HStack(spacing: 10) {
					_stat(String.localized("apps"), index.apps.count)
					_stat(String.localized("sources"), index.sources.count)
					_stat(String.localized("new 30d"), index.apps.filter(_store.isNew).count)
				}
			}
		}
		.padding(.top, 12)
	}

	private func _stat(_ label: String, _ value: Int) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: label.uppercased())
				.font(.accretionMono(10))
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: value.formatted())
				.font(.accretionDisplay(20))
				.foregroundStyle(AccretionTheme.fg)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.accretionCard()
	}

	private func _searchField() -> some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass").foregroundStyle(AccretionTheme.muted)
			TextField(String.localized("Search apps, developers, bundle IDs"), text: $_query)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.foregroundStyle(AccretionTheme.fg)
			if !_query.isEmpty {
				Button { _query = "" } label: { Image(systemName: "xmark.circle.fill") }
					.foregroundStyle(AccretionTheme.muted)
					.accessibilityLabel(String.localized("Clear search"))
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 11)
		.accretionCard()
	}

	private func _chips() -> some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				_chip(String.localized("All"), selected: _category == nil) { _category = nil; _shown = 60 }
				ForEach(StoreService.categoryOrder, id: \.self) { id in
					_chip(String.localized(StoreService.categoryNames[id] ?? id), selected: _category == id) {
						_category = _category == id ? nil : id
						_shown = 60
					}
				}
				_chip(String.localized("Works on my iOS"), selected: _onlyFitting) { _onlyFitting.toggle() }
			}
		}
	}

	private func _chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(verbatim: title)
				.font(.system(size: 14, weight: .medium))
				.padding(.horizontal, 13)
				.padding(.vertical, 7)
				.foregroundStyle(selected ? Color.white : AccretionTheme.fg)
				.background(selected ? AccretionTheme.accent : AccretionTheme.surface, in: Capsule())
				.overlay(Capsule().stroke(selected ? Color.clear : AccretionTheme.line, lineWidth: 1))
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	@ViewBuilder
	private func _list() -> some View {
		let apps = _store.apps(matching: _query, category: _category, onlyFitting: _onlyFitting)
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text(verbatim: _isBrowsing ? String.localized("Results") : String.localized("All apps"))
					.font(.accretionDisplay(20))
					.foregroundStyle(AccretionTheme.fg)
				Spacer()
				Text(verbatim: String.localized("%@ apps", arguments: apps.count.formatted()))
					.font(.accretionMono(11))
					.foregroundStyle(AccretionTheme.muted)
			}
			ForEach(apps.prefix(_shown)) { app in
				NavigationLink(value: app) {
					StoreAppCard(app: app)
				}
				.buttonStyle(.plain)
			}
			if apps.count > _shown {
				Button(String.localized("Show more")) { _shown += 60 }
					.buttonStyle(AccretionButtonStyle(prominent: false))
					.frame(maxWidth: .infinity)
			} else if apps.isEmpty {
				Text(verbatim: String.localized("Nothing matches. Try other words, or turn off Works on my iOS."))
					.font(.footnote)
					.foregroundStyle(AccretionTheme.muted)
			}
		}
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

// MARK: - Shelf
/// A titled shelf of apps, three rows per page, scrolling sideways like the web store's shelves.
struct StoreShelfView: View {
	let shelf: StoreService.Shelf

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(verbatim: String.localized(shelf.title))
					.font(.accretionDisplay(20))
					.foregroundStyle(AccretionTheme.fg)
				if let note = shelf.note {
					Text(verbatim: note)
						.font(.accretionMono(11))
						.foregroundStyle(AccretionTheme.muted)
				}
			}
			ScrollView(.horizontal, showsIndicators: false) {
				LazyHGrid(rows: Array(repeating: GridItem(.fixed(64), spacing: 8), count: min(3, shelf.apps.count)), spacing: 12) {
					ForEach(Array(shelf.apps.enumerated()), id: \.element.id) { index, app in
						NavigationLink(value: app) {
							StoreAppRow(app: app, rank: shelf.ranked ? index + 1 : nil)
								.frame(width: 300, alignment: .leading)
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
	}
}

// MARK: - Rows and cards
struct StoreAppIcon: View {
	let url: URL?
	var size: CGFloat = 52

	var body: some View {
		LazyImage(url: url) { state in
			if let image = state.image {
				image.resizable().scaledToFill()
			} else {
				AccretionTheme.raised
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}
}

/// Compact row for shelves: rank, icon, name, "v1.2 · Games · today"
struct StoreAppRow: View {
	@ObservedObject private var _store = StoreService.shared
	let app: StoreApp
	var rank: Int?

	var body: some View {
		HStack(spacing: 12) {
			if let rank {
				Text(verbatim: "\(rank)")
					.font(.accretionDisplay(17))
					.foregroundStyle(AccretionTheme.muted)
					.frame(width: 22)
			}
			StoreAppIcon(url: app.iconURL)
			VStack(alignment: .leading, spacing: 3) {
				Text(verbatim: app.n)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(AccretionTheme.fg)
					.lineLimit(1)
				HStack(spacing: 6) {
					if _store.isMod(app) { AccretionBadge(text: "Accretion Mod", color: AccretionTheme.accent) }
					Text(verbatim: StoreFormat.meta(app))
						.font(.caption)
						.foregroundStyle(AccretionTheme.muted)
						.lineLimit(1)
				}
			}
			Spacer(minLength: 0)
			Image(systemName: "chevron.right")
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
		}
	}
}

/// Card for lists: icon, name with badges, developer, version · date · size
struct StoreAppCard: View {
	@ObservedObject private var _store = StoreService.shared
	let app: StoreApp

	var body: some View {
		HStack(spacing: 12) {
			StoreAppIcon(url: app.iconURL, size: 56)
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(verbatim: app.n)
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
					if _store.isMod(app) {
						AccretionBadge(text: "Accretion Mod", color: AccretionTheme.accent)
					} else if _store.isNew(app) {
						AccretionBadge(text: "new")
					}
				}
				Text(verbatim: app.d)
					.font(.footnote)
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(1)
				Text(verbatim: ["v\(app.v)", StoreFormat.since(app), app.z.map(StoreFormat.bytes)].compactMap { $0 }.joined(separator: " · "))
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
			}
			Spacer(minLength: 0)
		}
		.padding(12)
		.accretionCard()
	}
}

// MARK: - Formatting (same wording as the web store)
enum StoreFormat {
	static func since(_ app: StoreApp) -> String {
		guard app.u == nil, let date = StoreService.day(app.t) else { return String.localized("date unknown") }
		let days = Int(Date().timeIntervalSince(date) / 86400)
		switch days {
		case ..<1: return String.localized("today")
		case 1: return String.localized("yesterday")
		case 2..<30: return String.localized("%@d ago", arguments: String(days))
		case 30..<365: return String.localized("%@mo ago", arguments: String(days / 30))
		default: return String.localized("%@y ago", arguments: String(days / 365))
		}
	}

	static func meta(_ app: StoreApp) -> String {
		["v\(app.v)", StoreService.categoryNames[app.c], since(app)].compactMap { $0 }.joined(separator: " · ")
	}

	static func bytes(_ size: Int) -> String {
		ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
	}
}
