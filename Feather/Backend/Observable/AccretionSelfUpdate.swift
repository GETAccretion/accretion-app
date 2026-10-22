//
//  AccretionSelfUpdate.swift
//  Accretion
//

import Foundation

// MARK: - Accretion's own update
/// The newest Accretion version offered by the app's own source (app-repo-beta.json with
/// Settings → Beta Updates on, else app-repo.json), when it's newer than this copy. The alert
/// announces each version once; Settings keeps a Get Update row while this is set.
@MainActor
final class AccretionSelfUpdate: ObservableObject {
	static let shared = AccretionSelfUpdate()

	/// Newer than the installed copy, or nil
	@Published private(set) var latest: String?

	/// Reads the source again and returns the newer version, if any
	@discardableResult
	func refresh() async -> String? {
		guard
			let response = try? await URLSession.shared.data(from: UpdateManager.selfSource),
			let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
			let app = (json["apps"] as? [[String: Any]])?.first,
			let version = app["version"] as? String
		else {
			return latest
		}
		latest = UpdateManager.isVersion(version, newerThan: Bundle.main.version) ? version : nil
		return latest
	}
}
