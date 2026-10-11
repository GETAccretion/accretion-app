//
//  TweakLibraryView.swift
//  Accretion
//

import SwiftUI
import NimbleViews

// MARK: - View
/// Settings → Accretion → Tweak Library: every tweak in the catalog and the apps it's made for.
/// Adding one happens on the signing screen of a matching app (Advanced → Modify → Tweaks).
struct TweakLibraryView: View {
	@ObservedObject private var _catalog = TweakCatalog.shared

	var body: some View {
		NBList(.localized("Tweak Library")) {
			if _catalog.tweaks.isEmpty {
				Text(verbatim: _catalog.loadFailed
					? String.localized("Couldn't load the tweak library. Check your connection and try again.")
					: String.localized("Loading…"))
					.font(.footnote)
					.foregroundStyle(.secondary)
			} else {
				NBSection(.localized("Tweaks"), secondary: _catalog.tweaks.count.description) {
					ForEach(_catalog.tweaks) { tweak in
						TweakRowView(tweak: tweak) {
							if let project = tweak.projectURL {
								Button {
									UIApplication.open(project.absoluteString)
								} label: {
									Image(systemName: "arrow.up.right")
								}
								.buttonStyle(.borderless)
								.accessibilityLabel(.localized("Open Project"))
							}
						}
					}
				} footer: {
					Text(.localized("To add a tweak, sign one of its apps and open Advanced → Modify → Tweaks. Tweaks download from their own projects."))
				}
			}
		}
		.task { await _catalog.load() }
		.refreshable { await _catalog.load() }
		.accretionList()
	}
}
