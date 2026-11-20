//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case discover // Accretion: the store, first like on the web
	case sources
	case library
	case settings
	case certificates
	case search // Accretion: the whole store's search, last in the tab bar
	
	var title: String {
		switch self {
		case .discover:	return .localized("Discover")
		case .sources:     	return .localized("Sources")
		case .library: 		return .localized("Library")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		case .search:		return .localized("Search")
		}
	}
	
	var icon: String {
		switch self {
		case .discover:	return "sparkles"
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		case .search:		return "magnifyingglass"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .discover: DiscoverView()
		case .sources: SourcesView()
		case .library: LibraryView()
		case .settings: AccretionSettingsView() // Accretion: own Settings screen (Feather's SettingsView removed)
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		case .search: SearchView()
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
			.discover,
			.library,
			.sources,
			.settings,
			.search
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
