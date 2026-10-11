//
//  AutoSignPipeline.swift
//  Accretion
//

import CoreData
import Foundation
import UIKit
import Zsign

// MARK: - Pipeline
/// One tap from "update available" to the install prompt: download → import → preflight →
/// sign with the app's recipe → install. Updates happen in place: same bundle ID and a
/// certificate from the same team as the installed copy, so iOS replaces the app and keeps its
/// data, and Library keeps one entry per app. Also re-signs every app after a certificate change.
@MainActor
final class AutoSignPipeline: ObservableObject {
	static let shared = AutoSignPipeline()

	/// What's happening now, for the Library banner; nil when idle
	@Published private(set) var status: String?
	/// A signed app ready for its install screen; the app root presents it from any tab
	@Published var pendingInstall: AnyApp?
	/// The store app being installed, so only its page shows the status line
	@Published private(set) var activeBundleID: String?
	var isRunning: Bool { status != nil }

	private init() {}

	enum PipelineError: LocalizedError {
		case noCertificate
		case download(String)
		case importNotFound
		case blocked(String)
		case unauthorized

		var errorDescription: String? {
			switch self {
			case .noCertificate: return String.localized("No certificate selected. Add one in Settings → Certificates.")
			case .download(let reason): return String.localized("Download failed: %@", arguments: reason)
			case .importNotFound: return String.localized("The download didn't import as an app.")
			case .blocked(let reason): return reason
			case .unauthorized: return String.localized("Sign in to your Accretion account to download this app.")
			}
		}
	}

	private var _selectedCertificate: CertificatePair? {
		Storage.shared.getCertificate(for: UserDefaults.standard.integer(forKey: "feather.selectedCert"))
	}

	// MARK: Updates
	/// Updates apps in order. With one signed app the install screen opens when it's ready; with
	/// several, they wait at the top of Library > Signed, since iOS asks to confirm each install.
	func update(_ all: [AppUpdate]) {
		// a signed and an imported copy of one app share an update: do it once
		var seen = Set<String>()
		let updates = all.filter { seen.insert("\($0.bundleIdentifier)@\($0.remoteVersion)").inserted }
		guard !isRunning, !updates.isEmpty else { return }
		Task {
			var done: [String] = []
			var signed = 0
			var failures: [String] = []
			for (index, update) in updates.enumerated() {
				status = updates.count == 1
					? String.localized("Updating %@…", arguments: update.appName)
					: String.localized("Updating %@ (%@ of %@)…", arguments: update.appName, String(index + 1), String(updates.count))
				do {
					if try await _update(update) { signed += 1 }
					done.append(update.appName)
				} catch {
					failures.append("\(update.appName): \(error.localizedDescription)")
				}
			}
			status = nil
			_finish(done: done, failures: failures, verb: String.localized("updated"), installSingle: updates.count == 1 && signed == 1)
		}
	}

	/// Returns whether a signed copy was produced (false when the app was only ever imported).
	private func _update(_ update: AppUpdate) async throws -> Bool {
		try await _fetchAndSign(
			bundleID: update.bundleIdentifier,
			downloadURL: update.downloadURL,
			provenance: update.sourceProvenance,
			localUUID: update.localUUID,
			signNew: false
		)
	}
	
	// MARK: Install from the store
	/// Installs an app from the Accretion store: download, sign with its recipe (if it has one)
	/// and open the install screen. Already installed? Then this is an in-place update.
	func install(name: String, bundleID: String, downloadURL: URL) {
		guard !isRunning else { return }
		Task {
			status = String.localized("Getting %@…", arguments: name)
			activeBundleID = bundleID
			defer { activeBundleID = nil }
			do {
				_ = try await _fetchAndSign(bundleID: bundleID, downloadURL: downloadURL, provenance: nil, localUUID: nil, signNew: true)
				status = nil
				_finish(done: [name], failures: [], verb: String.localized("installed"), installSingle: true)
			} catch {
				status = nil
				_finish(done: [], failures: ["\(name): \(error.localizedDescription)"], verb: "", installSingle: false)
			}
		}
	}
	
	/// Download → import (replacing the old imported copy) → sign in place over the installed
	/// copy, or as a new app when `signNew`. Returns whether a signed copy was produced.
	private func _fetchAndSign(
		bundleID: String,
		downloadURL: URL,
		provenance: SourceAppProvenance?,
		localUUID: String?,
		signNew: Bool
	) async throws -> Bool {
		let installed = _installedCopy(uuid: localUUID, bundleID: bundleID)
		let oldImported = localUUID.flatMap { _imported(uuid: $0) }
		if installed != nil || signNew, _usableCertificate(installed?.certificate) == nil, _selectedCertificate == nil {
			throw PipelineError.noCertificate
		}
		
		// Accretion: Accretion's own builds come from the store's download server. A refused key
		// was probably replaced on the website, so fetch the current one and try once more.
		let ipa: URL
		do {
			ipa = try await _download(await AccretionAccount.shared.downloadURL(for: bundleID, fallback: downloadURL))
		} catch PipelineError.unauthorized {
			AccretionAccount.shared.forgetDownloadKey()
			ipa = try await _download(await AccretionAccount.shared.downloadURL(for: bundleID, fallback: downloadURL))
		}
		defer { try? FileManager.default.removeItem(at: ipa) }
		
		let started = Date().addingTimeInterval(-1)
		try await _import(ipa, provenance: provenance)
		guard let imported = _newestImported(identifier: bundleID, since: started) else {
			throw PipelineError.importNotFound
		}
		// the new download replaces the old unsigned copy instead of sitting next to it
		if let oldImported { Storage.shared.deleteApp(for: oldImported) }
		
		if let installed {
			// the download only exists to be signed; the new signed copy replaces the old one
			try await _sign(imported, replacing: [imported, installed], updating: installed, preferInstalledCertificate: true)
			return true
		}
		guard signNew else { return false } // never signed: the updated IPA in Library is the update
		try await _sign(imported, replacing: [imported], updating: nil)
		return true
	}

	// MARK: Re-sign all
	/// Re-signs every signed app with the selected certificate, keeping each app's recipe and
	/// bundle ID, and replaces the old copies.
	func resignAll() {
		guard !isRunning else { return }
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
		let apps = (try? Storage.shared.context.fetch(request)) ?? []
		guard !apps.isEmpty else { return }

		Task {
			var done: [String] = []
			var failures: [String] = []
			var newTeam: [String] = []
			for (index, app) in apps.enumerated() {
				let name = app.name ?? String.localized("Unknown")
				status = String.localized("Re-signing %@ (%@ of %@)…", arguments: name, String(index + 1), String(apps.count))
				do {
					// a revoked certificate is usually replaced by another team's, so re-signing
					// can't always be in place; those apps are named at the end
					let sameTeam = try await _sign(app, replacing: [app], updating: app, requireSameTeam: false)
					done.append(name)
					if !sameTeam { newTeam.append(name) }
				} catch {
					failures.append("\(name): \(error.localizedDescription)")
				}
			}
			status = nil
			if !newTeam.isEmpty {
				failures.append(String.localized("Signed by a different team than the installed copies, so iOS needs these deleted from the Home Screen before installing (their data is lost): %@", arguments: newTeam.joined(separator: ", ")))
			}
			_finish(done: done, failures: failures, verb: String.localized("re-signed"), installSingle: apps.count == 1 && newTeam.isEmpty)
		}
	}

	// MARK: Lookups
	/// The signed copy of an app, which is what's installed on the device: the update's own entry
	/// if it is one, otherwise the newest signed app with that original bundle ID.
	private func _installedCopy(uuid: String?, bundleID: String) -> Signed? {
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		let signed = (try? Storage.shared.context.fetch(request)) ?? []
		return signed.first { uuid != nil && $0.uuid == uuid }
			?? signed.first { $0.identifier == bundleID || RecipeStore.key(for: $0) == bundleID }
	}

	private func _imported(uuid: String) -> Imported? {
		let request: NSFetchRequest<Imported> = Imported.fetchRequest()
		request.predicate = NSPredicate(format: "uuid == %@", uuid)
		request.fetchLimit = 1
		return (try? Storage.shared.context.fetch(request))?.first
	}

	private func _newestImported(identifier: String, since: Date) -> Imported? {
		let request: NSFetchRequest<Imported> = Imported.fetchRequest()
		request.predicate = NSPredicate(format: "date >= %@", since as NSDate)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		let recent = (try? Storage.shared.context.fetch(request)) ?? []
		return recent.first { $0.identifier == identifier } ?? recent.first
	}

	/// A certificate that can still sign: present, not revoked, not expired.
	private func _usableCertificate(_ cert: CertificatePair?) -> CertificatePair? {
		guard let cert, !cert.revoked else { return nil }
		if let expiration = cert.expiration, expiration < Date() { return nil }
		return cert
	}

	private func _team(of cert: CertificatePair?) -> String? {
		guard let cert else { return nil }
		return Storage.shared.getProvisionFileDecoded(for: cert)?.TeamIdentifier.first
	}

	// MARK: Inject (Library → ✨ → Inject Tweaks)
	/// Injects tweaks into an imported, decrypted app. Signs it with the selected certificate and
	/// opens the install screen, or with `exportOnly` only modifies it (no certificate needed) and
	/// opens the share sheet with the modded IPA for another signer.
	func inject(_ app: Imported, options: Options, remember: Bool, exportOnly: Bool) {
		guard !isRunning else { return }
		Task {
			status = String.localized("Injecting into %@…", arguments: app.name ?? "")
			let started = Date().addingTimeInterval(-1)
			do {
				var options = options
				options.post_installAppAfterSigned = false
				options.post_deleteAppAfterSigned = false // keep the original to inject into again
				if exportOnly {
					options.signingOption = .onlyModify
					if let problem = Preflight.problems(for: app, certificate: nil, options: options).first(where: \.isBlocking) {
						throw PipelineError.blocked("\(problem.title). \(problem.message)")
					}
					try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
						FR.signPackageFile(app, using: options, icon: nil, certificate: nil) { error in
							if let error { continuation.resume(throwing: error) } else { continuation.resume() }
						}
					}
				} else {
					options.signingOption = .default
					try await _sign(app, replacing: [], updating: nil, optionsOverride: options)
				}
				if remember {
					options.signingOption = .default
					RecipeStore.save(options: options, icon: nil, for: app)
				}
				status = nil
				let request: NSFetchRequest<Signed> = Signed.fetchRequest()
				request.predicate = NSPredicate(format: "date >= %@", started as NSDate)
				request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
				request.fetchLimit = 1
				if let result = (try? Storage.shared.context.fetch(request))?.first {
					pendingInstall = AnyApp(base: result, archive: exportOnly)
				}
			} catch {
				status = nil
				UIAlertController.showAlertWithOk(title: String.localized("Couldn't inject"), message: InstallErrorText.describe(error))
			}
		}
	}

	// MARK: Steps
	/// Downloads to a temporary .ipa, showing the percentage after the current status text.
	private func _download(_ url: URL) async throws -> URL {
		let label = status ?? ""
		let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ipa")
		var observation: NSKeyValueObservation?
		defer { observation?.invalidate() }
		let response: URLResponse? = try await withCheckedThrowingContinuation { continuation in
			let task = URLSession.shared.downloadTask(with: url) { temp, response, error in
				// the temporary file is gone once this handler returns, so move it here
				if let temp {
					do {
						try FileManager.default.moveItem(at: temp, to: ipa)
					} catch {
						continuation.resume(throwing: error)
						return
					}
				}
				if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: response) }
			}
			var shown = -1
			observation = task.progress.observe(\.fractionCompleted) { progress, _ in
				let percent = Int(progress.fractionCompleted * 100)
				guard percent != shown, !label.isEmpty else { return }
				shown = percent
				Task { @MainActor in
					if self.isRunning { self.status = "\(label) \(percent)%" }
				}
			}
			task.resume()
		}
		if !label.isEmpty { status = label }
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			try? FileManager.default.removeItem(at: ipa)
			if http.statusCode == 401 || http.statusCode == 403 {
				throw PipelineError.unauthorized
			}
			throw PipelineError.download("HTTP \(http.statusCode)")
		}
		return ipa
	}

	private func _import(_ ipa: URL, provenance: SourceAppProvenance?) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			FR.handlePackageFile(ipa, sourceProvenance: provenance) { error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}
	}

	/// Signs `app` the way SigningView would (recipe or defaults, certificate slot, PPQ, global
	/// renaming rules, preflight), then deletes `old`. When `installed` is given, the result keeps
	/// its bundle ID and, for in-place installs, needs a certificate from the same team.
	/// Returns whether the certificate's team matches the installed copy's (true when unknown).
	@discardableResult
	private func _sign(
		_ app: AppInfoPresentable,
		replacing old: [AppInfoPresentable],
		updating installed: Signed?,
		preferInstalledCertificate: Bool = false,
		requireSameTeam: Bool = true,
		optionsOverride: Options? = nil
	) async throws -> Bool {
		// updates keep the certificate the installed copy was signed with while it's still good
		let preferred = preferInstalledCertificate ? _usableCertificate(installed?.certificate) : nil
		guard let cert = preferred ?? _selectedCertificate else { throw PipelineError.noCertificate }

		let installedTeam = _team(of: installed?.certificate)
		let sameTeam = installedTeam == nil || installedTeam == _team(of: cert)
		if requireSameTeam, !sameTeam {
			throw PipelineError.blocked(String.localized("The installed copy was signed by a different certificate team, so iOS can't update it in place. Select a certificate from the same team, or delete the app from your Home Screen first (its data is lost) and use Re-sign All."))
		}

		let base = OptionsManager.shared.options
		let recipe = optionsOverride == nil ? RecipeStore.load(for: app, base: base) : nil
		var options = optionsOverride ?? recipe?.options ?? base
		let icon = recipe?.icon
		var kind = CertificateSlots.kind(of: cert)
		// several profiles: this app keeps its own, so its bundle ID (and in-place updates) stay stable
		if let key = RecipeStore.key(for: app) ?? app.identifier,
		   ProfileStore.profiles(for: cert).count > 1,
		   let choice = ProfileStore.choose(for: key, cert: cert, assign: true) {
			ProfileOverride.set(choice.profile.url, for: cert)
			kind = choice.profile.kind
		}
		defer { ProfileOverride.set(nil, for: cert) }

		if let original = app.identifier {
			if let renamed = options.identifiers[original] { options.appIdentifier = renamed }
			if options.ppqProtection, cert.ppQCheck, options.appIdentifier == nil {
				options.appIdentifier = "\(original).\(options.ppqString)"
			}
			let fitted = CertificateSlots.bundleID(options.appIdentifier ?? original, for: kind)
			if fitted != (options.appIdentifier ?? original) { options.appIdentifier = fitted }
		}
		// in place: same bundle ID as what's installed, unless the profile allows only one other ID
		if let installedID = installed?.identifier, CertificateSlots.bundleID(installedID, for: kind) == installedID {
			options.appIdentifier = installedID
		}
		if let name = app.name, let renamed = options.displayNames[name] { options.appName = renamed }
		options.post_installAppAfterSigned = false // the pipeline opens the install screen itself

		if let problem = Preflight.problems(for: app, certificate: cert, options: options).first(where: \.isBlocking) {
			throw PipelineError.blocked("\(problem.title). \(problem.message)")
		}

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			FR.signPackageFile(app, using: options, icon: icon, certificate: cert) { error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}

		if recipe != nil {
			RecipeStore.save(options: options, icon: icon, for: app) // keeps the signed-as bundle ID current
		}
		for entry in old {
			Storage.shared.deleteApp(for: entry)
		}
		return sameTeam
	}

	private func _finish(done: [String], failures: [String], verb: String, installSingle: Bool) {
		if installSingle, done.count == 1, failures.isEmpty {
			// the root view opens the install screen for the newest signed app, whichever tab is showing
			let request: NSFetchRequest<Signed> = Signed.fetchRequest()
			request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
			request.fetchLimit = 1
			if let newest = (try? Storage.shared.context.fetch(request))?.first {
				pendingInstall = AnyApp(base: newest)
			}
			return
		}
		var lines: [String] = []
		if !done.isEmpty {
			lines.append(String.localized("%@ apps %@. Install signed ones from Library → Signed.", arguments: String(done.count), verb))
		}
		if !failures.isEmpty {
			lines.append(String.localized("Needs attention:") + "\n" + failures.joined(separator: "\n"))
		}
		UIAlertController.showAlertWithOk(title: String.localized("Done"), message: lines.joined(separator: "\n\n"))
	}
}

// MARK: - Revocation
extension Storage {
	/// Asks OCSP again even when a certificate is already flagged, so a replaced or wrongly
	/// flagged certificate recovers. Zsign status: 0 good, 1 revoked, 2 unknown or error.
	func recheckRevocation(for cert: CertificatePair, completion: @escaping (_ revoked: Bool) -> Void) {
		Zsign.checkRevokage(
			provisionPath: getFile(.provision, from: cert)?.path ?? "",
			p12Path: getFile(.certificate, from: cert)?.path ?? "",
			p12Password: cert.password ?? ""
		) { status, _, _ in
			DispatchQueue.main.async {
				if status == 1 { cert.revoked = true }
				if status == 0 { cert.revoked = false }
				self.saveContext()
				completion(cert.revoked)
			}
		}
	}
}
