//
//  StoreDestinations.swift
//  Accretion
//

import SwiftUI

// MARK: - Store destinations
extension View {
	/// Every store page a NavigationLink(value:) can open, so a store app, list or guide opens the
	/// same way from Discover, Search, Library (Saved) and Sources. Put it inside each tab's
	/// NavigationStack, once.
	func accretionStoreDestinations() -> some View {
		self
			.navigationDestination(for: StoreApp.self) { StoreAppView(app: $0) }
			.navigationDestination(for: StoreListRoute.self) { StoreListView(route: $0) }
			.navigationDestination(for: SignGuideRoute.self) { _ in SignGuideView() }
			.navigationDestination(for: StatusRoute.self) { _ in StatusView() }
			.navigationDestination(for: CommunityFeedRoute.self) { CommunityFeedView(whatsNew: $0.whatsNew) }
			.navigationDestination(for: NotificationsRoute.self) { _ in NotificationsView() }
			.navigationDestination(for: StoreSourcesRoute.self) { _ in StoreSourcesView() }
	}
}
