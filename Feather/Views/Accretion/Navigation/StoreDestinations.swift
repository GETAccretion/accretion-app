//
//  StoreDestinations.swift
//  Accretion
//

import SwiftUI

// MARK: - Store destinations
extension View {
	/// Every store page a NavigationLink(value:) can open, so a store app, list or guide opens the
	/// same way from Discover, Search, Library (Saved) and Sources. Put it inside each tab's
	/// NavigationStack, once. With `zoom`, app pages grow from the icon marked with
	/// `accretionZoomSource` (iOS 18 and later).
	func accretionStoreDestinations(zoom: Namespace.ID? = nil) -> some View {
		self
			.navigationDestination(for: StoreApp.self) { app in
				if let zoom {
					StoreAppView(app: app).accretionZoomDestination(app.i, in: zoom)
				} else {
					StoreAppView(app: app)
				}
			}
			.navigationDestination(for: StoreListRoute.self) { StoreListView(route: $0) }
			.navigationDestination(for: SignGuideRoute.self) { _ in SignGuideView() }
			.navigationDestination(for: StatusRoute.self) { _ in StatusView() }
			.navigationDestination(for: CommunityFeedRoute.self) { CommunityFeedView(whatsNew: $0.whatsNew) }
			.navigationDestination(for: NotificationsRoute.self) { _ in NotificationsView() }
			.navigationDestination(for: StoreSourcesRoute.self) { _ in StoreSourcesView() }
	}
}
