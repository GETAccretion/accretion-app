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
	/// in its own sources (the store, Accretion Mods, personal source links; see AccretionSources)
	/// for the same bundle ID, and takes the newest strictly higher version, so a mod or tweak
	/// hosted there still gets its updates and nothing ever downgrades. Any other source may only
	/// update the apps that came from it, so one added source can't offer a "newer version" of
	/// every installed app. These updates are marked `crossSource`: announced, never auto-signed.
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
					AccretionSources.trustsForCrossSourceUpdates(sourceURL, accountHost: AccretionAccount.accountHost),
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
				sourceProvenance: provenance,
				crossSource: true
			)
		}

		return updates
	}

	/// Compares dotted versions number by number ("1.10" is newer than "1.9"); anything that isn't
	/// a number is ignored, so "2.0b" compares as "2.0".
	nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
		AccretionVersion.isNewer(candidate, than: current) // Core, unit-tested
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
		let localApps =
			((try? context.fetch(signedRequest)) ?? []).map { $0 as AppInfoPresentable } +
			((try? context.fetch(importedRequest)) ?? []).map { $0 as AppInfoPresentable }
		
		if !sources.isEmpty {
			await checkForUpdates(sources: sources, localApps: localApps)
			// "Update apps automatically": download and sign right away, so only iOS's install
			// prompt is left; signing replaces the old copies, so the same update won't repeat.
			// An update from a source other than the one the app came from is only announced:
			// it is never signed with the user's certificate on its own.
			if UserDefaults.standard.bool(forKey: Self.autoInstallKey), !updates.isEmpty {
				let sameSource = updates.values.filter { !$0.crossSource }
				if !sameSource.isEmpty { AutoSignPipeline.shared.update(sameSource) }
				_alertNewUpdates(updates.values.filter(\.crossSource))
			} else {
				_alertNewUpdates(Array(updates.values))
			}
		}
		_recheckSelectedCertificate()
		await _checkSelfUpdate()
	}
	
	// MARK: Accretion's own updates
	nonisolated static let autoInstallKey = "accretion.autoInstallUpdates"
	/// Settings → Beta Updates: offer test builds (versions like 1.0.25.1, between two releases)
	nonisolated static let betaKey = "accretion.betaUpdates"
	private static let _selfAlertedKey = "accretion.alertedSelfUpdate"
	/// Where Accretion learns about its own new versions: app-repo-beta.json lists the newest of
	/// betas and releases, app-repo.json releases only
	nonisolated static var selfSource: URL {
		let beta = UserDefaults.standard.bool(forKey: betaKey)
		return URL(string: "https://raw.githubusercontent.com/GETAccretion/accretion-app/main/\(beta ? "app-repo-beta.json" : "app-repo.json")")!
	}
	private static var _selfSource: URL { selfSource }
	
	/// Accretion can't install over itself with the server method, so a new version is announced
	/// once with its download link; with the idevice method it can install itself directly.
	private func _checkSelfUpdate() async {
		guard
			let response = try? await URLSession.shared.data(from: Self._selfSource),
			let json = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
			let app = (json["apps"] as? [[String: Any]])?.first,
			let latest = app["version"] as? String,
			let link = (app["downloadURL"] as? String).flatMap(URL.init(string:)),
			Self.isVersion(latest, newerThan: Bundle.main.version),
			UserDefaults.standard.string(forKey: Self._selfAlertedKey) != latest,
			UIApplication.topViewController() != nil
		else {
			return
		}
		UserDefaults.standard.set(latest, forKey: Self._selfAlertedKey)
		
		// the link goes through the download server with the personal key (AppPolicy)
		_ = link
		let installsDirectly = UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1
		let actions = [UIAlertAction(title: installsDirectly ? String.localized("Install Now") : String.localized("Get Update"), style: .default) { _ in
			Task { await AppPolicy.shared.getUpdate() }
		}]
		UIAlertController.showAlertWithCancel(
			title: String.localized("Accretion %@ is available", arguments: latest),
			message: String.localized("You have %@. Get Update opens the new IPA: install it with the tool you used for Accretion (for example your certificate seller's signer).", arguments: Bundle.main.version),
			actions: actions
		)
	}

	/// Re-asks OCSP about the certificate used for signing; warns once when it becomes revoked,
	/// and clears the flag again when a check says it's good.
	private func _recheckSelectedCertificate() {
		guard let cert = Storage.shared.getCertificate(for: UserDefaults.standard.integer(forKey: "feather.selectedCert")) else { return }
		let wasRevoked = cert.revoked
		Storage.shared.recheckRevocation(for: cert) { revoked in
			guard revoked, !wasRevoked, UIApplication.topViewController() != nil else { return }
			UIAlertController.showAlertWithOk(
				title: String.localized("Certificate revoked"),
				message: String.localized("Apple has revoked the certificate you sign with, so apps signed with it will stop opening. Import or pick another certificate in Settings → Certificates, then use Re-sign All from the ✨ menu in Library.")
			)
		}
	}

	private func _alertNewUpdates(_ candidates: [AppUpdate]) {
		let alerted = Set(UserDefaults.standard.stringArray(forKey: Self._alertedKey) ?? [])
		// one entry per app and version, so a signed and an imported copy alert once together
		var fresh: [String: AppUpdate] = [:]
		for update in candidates where !alerted.contains("\(update.bundleIdentifier)@\(update.remoteVersion)") {
			fresh["\(update.bundleIdentifier)@\(update.remoteVersion)"] = update
		}
		// the alert helper presents on the top view controller; wait for the next check if there's none yet
		guard !fresh.isEmpty, UIApplication.topViewController() != nil else { return }
		UserDefaults.standard.set(Array(alerted.union(fresh.keys)), forKey: Self._alertedKey)

		let lines = fresh.values
			.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
			.map { update in
				let line = "\(update.appName) \(update.localVersion ?? "?") → \(update.remoteVersion)"
				// name the source when it isn't the one the app came from, so the user can judge it
				guard update.crossSource else { return line }
				let source = update.sourceProvenance.sourceRepositoryName ?? update.sourceURL.host ?? update.sourceURL.absoluteString
				return line + " " + String.localized("(from %@)", arguments: source)
			}
		let title: String = fresh.count == 1
			? String.localized("Update available")
			: String.localized("%@ updates available", arguments: String(fresh.count))
		let message: String = lines.joined(separator: "\n") + "\n\n" + String.localized("Open Library to update.")
		UIAlertController.showAlertWithOk(title: title, message: message)
	}
}
