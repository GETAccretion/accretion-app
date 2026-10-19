//
//  SearchView.swift
//  Accretion
//

import SwiftUI
import UIKit

// MARK: - Search
/// The Search tab: the system search field over the whole store, in the web store's card style.
/// Before anything is typed it lists the categories; results follow Discover's iOS filter and sort.
struct SearchView: View {
	@ObservedObject private var _store = StoreService.shared
	// the same settings as Discover's All apps, so both lists agree
	@AppStorage("accretion.discover.onlyFitting") private var _onlyFitting = true
	@AppStorage("accretion.discover.sort") private var _sort: StoreService.Sort = .updated
	@State private var _query = ""
	/// What the list searches for: the typed text once typing pauses (150 ms, like Discover)
	@State private var _search = ""
	@State private var _shown = 60

	var body: some View {
		NavigationStack {
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 12) {
					if _store.index == nil {
						_placeholder()
					} else if _search.isEmpty {
						_categories()
					} else {
						_results()
					}
				}
				.padding(.horizontal, 16)
				.padding(.top, 8)
				.padding(.bottom, 40)
			}
			.scrollDismissesKeyboard(.immediately)
			.accretionBackground()
			.navigationTitle(String.localized("Search"))
			.searchable(
				text: $_query,
				placement: .navigationBarDrawer(displayMode: .always),
				prompt: Text(verbatim: String.localized("Search apps, developers, bundle IDs"))
			)
			.textInputAutocapitalization(.never)
			.autocorrectionDisabled()
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) { _filterMenu() }
			}
			.accretionStoreDestinations()
		}
		.tint(AccretionTheme.accent)
		.task { await _store.load() }
		.task(id: _query) {
			if !_query.isEmpty { try? await Task.sleep(nanoseconds: 150_000_000) }
			guard !Task.isCancelled else { return }
			_search = _query.trimmingCharacters(in: .whitespaces)
			_shown = 60
		}
	}

	// MARK: Sort and iOS filter (Discover's controls, as a menu)
	private func _filterMenu() -> some View {
		Menu {
			Picker(String.localized("Sort"), selection: $_sort) {
				ForEach(StoreService.Sort.allCases) { Text(verbatim: $0.title).tag($0) }
			}
			.pickerStyle(.inline)
			Toggle(isOn: $_onlyFitting) {
				Text(verbatim: String.localized("Only apps for iOS %@", arguments: UIDevice.current.systemVersion))
			}
		} label: {
			Image(systemName: "line.3.horizontal.decrease.circle")
		}
		.accessibilityLabel(String.localized("Sort and filter"))
		.onChange(of: _onlyFitting) { _ in _shown = 60 }
	}

	// MARK: Categories (nothing typed yet)
	@ViewBuilder
	private func _categories() -> some View {
		let counts = _store.categoryCounts()
		let ids = StoreService.categoryOrder.filter { counts[$0] != nil }
		Text(verbatim: String.localized("Browse by category"))
			.font(.accretionDisplay(20))
			.foregroundStyle(AccretionTheme.fg)
			.accessibilityAddTraits(.isHeader)
		VStack(spacing: 0) {
			ForEach(Array(ids.enumerated()), id: \.element) { position, id in
				let name = String.localized(StoreService.categoryNames[id] ?? id)
				NavigationLink(value: StoreListRoute(title: name, category: id)) {
					HStack(spacing: 12) {
						Text(verbatim: name)
							.accretionFont(15, weight: .semibold)
							.foregroundStyle(AccretionTheme.fg)
						Spacer(minLength: 0)
						Text(verbatim: (counts[id] ?? 0).formatted())
							.font(.accretionMono(12, weight: .regular))
							.foregroundStyle(AccretionTheme.muted)
						Text(verbatim: "›")
							.accretionFont(22)
							.foregroundStyle(AccretionTheme.muted)
							.accessibilityHidden(true)
					}
					.padding(.horizontal, 14)
					.frame(minHeight: 52)
					.overlay(alignment: .top) { if position > 0 { AccretionTheme.line.frame(height: 1) } }
					.contentShape(Rectangle())
				}
				.buttonStyle(AccretionPressStyle())
			}
		}
		.accretionCard()
	}

	// MARK: Results
	@ViewBuilder
	private func _results() -> some View {
		let apps = _store.apps(matching: _search, category: nil, onlyFitting: _onlyFitting, sort: _sort)
		Text(verbatim: String.localized("%@ apps", arguments: apps.count.formatted()))
			.font(.accretionMono(12, weight: .regular))
			.foregroundStyle(AccretionTheme.muted)
		ForEach(apps.prefix(_shown)) { app in
			NavigationLink(value: app) { StoreAppCard(app: app) }
				.buttonStyle(AccretionPressStyle())
		}
		if apps.count > _shown {
			Button(String.localized("Show more")) { _shown += 60 }
				.buttonStyle(AccretionButtonStyle(prominent: false))
				.frame(maxWidth: .infinity)
				.padding(.top, 6)
		} else if apps.isEmpty {
			Text(verbatim: _onlyFitting
				? String.localized("Nothing matches. Try other words, or turn off the iOS filter.")
				: String.localized("Nothing matches. Try other words."))
				.accretionFont(13)
				.foregroundStyle(AccretionTheme.muted)
			if _onlyFitting {
				Button(String.localized("Show apps for every iOS version")) { _onlyFitting = false }
					.buttonStyle(AccretionButtonStyle(prominent: false))
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
