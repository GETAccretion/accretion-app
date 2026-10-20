//
//  AccretionZoom.swift
//  Accretion
//

import SwiftUI

// MARK: - Icon zoom
/// An app's icon grows into its page when the page opens, and the page shrinks back into it
/// (iOS 18 and later; earlier versions slide in as before). The screen that owns the navigation
/// stack shares a namespace through the environment; app rows mark their icon as the source.
private struct AccretionZoomKey: EnvironmentKey {
	static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
	var accretionZoom: Namespace.ID? {
		get { self[AccretionZoomKey.self] }
		set { self[AccretionZoomKey.self] = newValue }
	}
}

private struct AccretionZoomSource: ViewModifier {
	@Environment(\.accretionZoom) private var _zoom
	let id: String

	func body(content: Content) -> some View {
		if let zoom = _zoom {
			if #available(iOS 18.0, *) {
				content.matchedTransitionSource(id: id, in: zoom)
			} else {
				content
			}
		} else {
			content
		}
	}
}

extension View {
	/// Marks an app icon as where that app's page zooms from
	func accretionZoomSource(_ id: String) -> some View {
		modifier(AccretionZoomSource(id: id))
	}

	/// The app page zooms from the icon marked with the same id
	@ViewBuilder
	func accretionZoomDestination(_ id: String, in namespace: Namespace.ID) -> some View {
		if #available(iOS 18.0, *) {
			navigationTransition(.zoom(sourceID: id, in: namespace))
		} else {
			self
		}
	}
}
