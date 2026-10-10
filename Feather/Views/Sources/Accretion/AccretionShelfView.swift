//
//  AccretionShelfView.swift
//  Accretion
//

import SwiftUI
import AltSourceKit
import NimbleViews

// MARK: - Accretion
/// Accretion's own store rules. Every mod built by Accretion (github.com/AccretionMods/mods) is
/// published under this bundle ID prefix, whichever source the user found it in.
enum Accretion {
	static let modPrefix = "io.github.accretionmods."

	static func isMod(_ app: ASRepository.App) -> Bool {
		app.id?.hasPrefix(modPrefix) ?? false
	}
}

// MARK: - View
/// "Made by Accretion" on the Sources tab: every Accretion Mod across the user's sources, once each.
struct AccretionShelfView: View {
	@ObservedObject var viewModel: SourcesViewModel

	private struct _Item: Identifiable {
		let id: String
		let sourceURL: URL?
		let source: ASRepository
		let app: ASRepository.App
	}

	private var _items: [_Item] {
		var seen = Set<String>()
		var items: [_Item] = []
		for (altSource, repository) in viewModel.sources {
			for app in repository.apps where Accretion.isMod(app) {
				guard let id = app.id, seen.insert(id).inserted else { continue }
				items.append(_Item(id: id, sourceURL: altSource.sourceURL, source: repository, app: app))
			}
		}
		return items.sorted { $0.app.currentName.localizedCaseInsensitiveCompare($1.app.currentName) == .orderedAscending }
	}

	// MARK: Body
	var body: some View {
		let items = _items
		if !items.isEmpty {
			NBSection(.localized("Made by Accretion"), secondary: items.count.description) {
				ForEach(items) { item in
					NavigationLink {
						SourceAppsDetailView(sourceURL: item.sourceURL, source: item.source, app: item.app)
					} label: {
						FRIconCellView(
							title: item.app.currentName,
							subtitle: SourceAppsCellView.appDescription(app: item.app),
							iconUrl: item.app.iconURL
						)
					}
					.buttonStyle(.plain)
				}
			} footer: {
				Text(.localized("Free and open-source apps with mods built in by Accretion. Sign them with your own certificate."))
			}
		}
	}
}
