//
//  AppPolicy.swift
//  Accretion
//

import Foundation
import UIKit

// MARK: - Minimum version
/// The oldest Accretion that may still be used, set in the store's app-config.json
/// ({"minimumVersion": "1.0.5"}). Older copies miss things like sign-in-only downloads, so
/// they get a full-screen "Update required" until they're updated. The last value seen is kept,
/// so going offline doesn't lift the block.
@MainActor
final class AppPolicy: ObservableObject {
	static let shared = AppPolicy()
	static let configURL = URL(string: "https://getaccretion.app/app-config.json")!
	private static var _selfSource: URL { UpdateManager.selfSource }
	private static let _minimumKey = "accretion.minimumVersion"

	@Published private(set) var minimumVersion: String? = UserDefaults.standard.string(forKey: AppPolicy._minimumKey)

	var isOutdated: Bool {
		guard let minimum = minimumVersion, !minimum.isEmpty else { return false }
		return UpdateManager.isVersion(minimum, newerThan: Bundle.main.version)
	}

	private init() {}

	func refresh() async {
		var request = URLRequest(url: Self.configURL)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		guard
			let (data, _) = try? await URLSession.shared.data(for: request),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			return
		}
		let minimum = json["minimumVersion"] as? String
		minimumVersion = minimum
		UserDefaults.standard.set(minimum, forKey: Self._minimumKey)
	}

	// MARK: Getting the newest Accretion
	/// The newest version and its link, with the personal key when signed in (the download
	/// server only hands builds to account holders).
	func latestRelease() async -> (version: String, link: URL)? {
		var request = URLRequest(url: Self._selfSource)
		request.cachePolicy = .reloadIgnoringLocalCacheData
		guard
			let (data, _) = try? await URLSession.shared.data(for: request),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let app = (json["apps"] as? [[String: Any]])?.first,
			let version = app["version"] as? String,
			let link = (app["downloadURL"] as? String).flatMap(URL.init(string:))
		else {
			return nil
		}
		let bundleID = Bundle.main.bundleIdentifier ?? "io.github.getaccretion.Accretion"
		return (version, await AccretionAccount.shared.downloadURL(for: bundleID, fallback: link))
	}

	/// Installs the update directly with the idevice method; otherwise opens the IPA to install
	/// with the tool used for Accretion itself (it can't install over itself through the server).
	func getUpdate() async {
		guard let release = await latestRelease() else {
			UIAlertController.showAlertWithOk(title: String.localized("Couldn't check for updates"), message: String.localized("Check your connection and try again."))
			return
		}
		if UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1 {
			AutoSignPipeline.shared.install(name: "Accretion", bundleID: Bundle.main.bundleIdentifier ?? "", downloadURL: release.link)
		} else {
			_ = await UIApplication.shared.open(release.link)
		}
	}
}
