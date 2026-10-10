//
//  UpdateManager+Accretion.swift
//  Accretion
//

import AltSourceKit
import CoreData
import Foundation
import UIKit

// MARK: - Updates from every source
extension UpdateManager {
	/// Feather only offers updates from the source an app was installed from. Accretion also looks
	/// in every other source for the same bundle ID, and takes the newest strictly higher version,
	/// so a mod or tweak hosted elsewhere still gets its updates and nothing ever downgrades.
	func addingCrossSourceUpdates(
		to found: [String: AppUpdate],
		repositories: [(AltSource, ASRepository)],
		localApps: [AppInfoPresentable],
		metadataByUUID: [String?: AppSourceMetadata] // keyed by the optional appUUID, as UpdateManager builds it
	) -> [String: AppUpdate] {
		var updates = found

		for localApp in localApps {
			guard let uuid = localApp.uuid, updates[uuid] == nil else { continue }
			guard
				let identifier = metadataByUUID[uuid]?.sourceAppIdentifier ?? localApp.identifier,
				let currentVersion = metadataByUUID[uuid]?.sourceAppVersion ?? localApp.version
			else {
				continue
			}

			var best: (sourceURL: URL, repository: ASRepository, app: ASRepository.App, version: String)?
			for (source, repository) in repositories {
				guard
					let sourceURL = source.sourceURL,
					let remoteApp = repository.apps.first(where: { $0.id == identifier }),
					let remoteVersion = remoteApp.currentVersion,
					remoteApp.currentDownloadUrl != nil,
					Self.isVersion(remoteVersion, newerThan: best?.version ?? currentVersion)
				else {
					continue
				}
				best = (sourceURL, repository, remoteApp, remoteVersion)
			}

			guard
				let best,
				let downloadURL = best.app.currentDownloadUrl,
				let provenance = SourceAppProvenance(sourceURL: best.sourceURL, repository: best.repository, app: best.app)
			else {
				continue
			}

			updates[uuid] = AppUpdate(
				id: uuid,
				localUUID: uuid,
				localVersion: currentVersion,
				remoteVersion: best.version,
				appName: best.app.currentName,
				bundleIdentifier: identifier,
				downloadURL: downloadURL,
				sourceURL: best.sourceURL,
				sourceProvenance: provenance
			)
		}

		return updates
	}

	/// Compares dotted versions number by number ("1.10" is newer than "1.9"); anything that isn't
	/// a number is ignored, so "2.0b" compares as "2.0".
	nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
		func numbers(_ version: String) -> [Int] {
			version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
		}
		let a = numbers(candidate), b = numbers(current)
		for i in 0..<max(a.count, b.count) {
			let x = i < a.count ? a[i] : 0
			let y = i < b.count ? b[i] : 0
			if x != y { return x > y }
		}
		return false
	}
}

// MARK: - Automatic checks and alerts
extension UpdateManager {
	nonisolated static let autoCheckKey = "accretion.autoUpdateCheck"
	private static let _alertedKey = "accretion.alertedUpdates"

	/// Runs at launch and whenever the app comes back to the front, at most once an hour, unless
	/// turned off in Settings. New updates get one alert each; the Library tab shows the count.
	func checkAutomatically() async {
		guard UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true else { return }
		if let last = lastCheckedDate, Date().timeIntervalSince(last) < 3600 { return }

		let context = Storage.shared.context
		let sourceRequest: NSFetchRequest<AltSource> = AltSource.fetchRequest()
		let signedRequest: NSFetchRequest<Signed> = Signed.fetchRequest()
		let importedRequest: NSFetchRequest<Imported> = Imported.fetchRequest()
		let sources = (try? context.fetch(sourceRequest)) ?? []
		guard !sources.isEmpty else { return }
		let localApps =
			((try? context.fetch(signedRequest)) ?? []).map { $0 as AppInfoPresentable } +
			((try? context.fetch(importedRequest)) ?? []).map { $0 as AppInfoPresentable }

		await checkForUpdates(sources: sources, localApps: localApps)
		_alertNewUpdates()
	}

	private func _alertNewUpdates() {
		let alerted = Set(UserDefaults.standard.stringArray(forKey: Self._alertedKey) ?? [])
		// one entry per app and version, so a signed and an imported copy alert once together
		var fresh: [String: AppUpdate] = [:]
		for update in updates.values where !alerted.contains("\(update.bundleIdentifier)@\(update.remoteVersion)") {
			fresh["\(update.bundleIdentifier)@\(update.remoteVersion)"] = update
		}
		// the alert helper presents on the top view controller; wait for the next check if there's none yet
		guard !fresh.isEmpty, UIApplication.topViewController() != nil else { return }
		UserDefaults.standard.set(Array(alerted.union(fresh.keys)), forKey: Self._alertedKey)

		let lines = fresh.values
			.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
			.map { "\($0.appName) \($0.localVersion ?? "?") → \($0.remoteVersion)" }
		let title: String = fresh.count == 1
			? String.localized("Update available")
			: String.localized("%@ updates available", arguments: String(fresh.count))
		let message: String = lines.joined(separator: "\n") + "\n\n" + String.localized("Open Library to update.")
		UIAlertController.showAlertWithOk(title: title, message: message)
	}
}
