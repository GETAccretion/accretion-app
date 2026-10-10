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
/// sign with the app's recipe and the selected certificate → install. Also re-signs every app
/// at once after a certificate is revoked or replaced.
@MainActor
final class AutoSignPipeline: ObservableObject {
	static let shared = AutoSignPipeline()

	/// What's happening now, for the Library banner; nil when idle
	@Published private(set) var status: String?
	var isRunning: Bool { status != nil }

	private init() {}

	enum PipelineError: LocalizedError {
		case noCertificate
		case download(String)
		case importNotFound
		case blocked(String)

		var errorDescription: String? {
			switch self {
			case .noCertificate: return String.localized("No certificate selected. Add one in Settings → Certificates.")
			case .download(let reason): return String.localized("Download failed: %@", arguments: reason)
			case .importNotFound: return String.localized("The download didn't import as an app.")
			case .blocked(let reason): return reason
			}
		}
	}

	private var _selectedCertificate: CertificatePair? {
		Storage.shared.getCertificate(for: UserDefaults.standard.integer(forKey: "feather.selectedCert"))
	}

	// MARK: Updates
	/// Updates apps in order. With one app the install screen opens when it's signed; with
	/// several, they wait at the top of Library > Signed, since iOS asks to confirm each install.
	func update(_ all: [AppUpdate]) {
		// a signed and an imported copy of one app share an update: do it once
		var seen = Set<String>()
		let updates = all.filter { seen.insert("\($0.bundleIdentifier)@\($0.remoteVersion)").inserted }
		guard !isRunning, !updates.isEmpty else { return }
		Task {
			var done: [String] = []
			var failures: [String] = []
			for (index, update) in updates.enumerated() {
				status = updates.count == 1
					? String.localized("Updating %@…", arguments: update.appName)
					: String.localized("Updating %@ (%@ of %@)…", arguments: update.appName, String(index + 1), String(updates.count))
				do {
					try await _update(update)
					done.append(update.appName)
				} catch {
					failures.append("\(update.appName): \(error.localizedDescription)")
				}
			}
			status = nil
			_finish(done: done, failures: failures, verb: String.localized("updated and signed"), installSingle: updates.count == 1)
		}
	}

	private func _update(_ update: AppUpdate) async throws {
		guard _selectedCertificate != nil else { throw PipelineError.noCertificate }
		let ipa = try await _download(update.downloadURL)
		defer { try? FileManager.default.removeItem(at: ipa) }

		let started = Date().addingTimeInterval(-1)
		try await _import(ipa, provenance: update.sourceProvenance)
		guard let imported = _newestImported(identifier: update.bundleIdentifier, since: started) else {
			throw PipelineError.importNotFound
		}
		// the downloaded copy only exists to be signed; the signed app and the recipe remain
		try await _sign(imported, replacing: imported)
	}

	// MARK: Re-sign all
	/// Re-signs every signed app with the selected certificate, keeping each app's recipe, and
	/// removes the old copy once the new one is signed.
	func resignAll() {
		guard !isRunning else { return }
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
		let apps = (try? Storage.shared.context.fetch(request)) ?? []
		guard !apps.isEmpty else { return }

		Task {
			var done: [String] = []
			var failures: [String] = []
			for (index, app) in apps.enumerated() {
				let name = app.name ?? String.localized("Unknown")
				status = String.localized("Re-signing %@ (%@ of %@)…", arguments: name, String(index + 1), String(apps.count))
				do {
					try await _sign(app, replacing: app)
					done.append(name)
				} catch {
					failures.append("\(name): \(error.localizedDescription)")
				}
			}
			status = nil
			_finish(done: done, failures: failures, verb: String.localized("re-signed"), installSingle: apps.count == 1)
		}
	}

	// MARK: Steps
	private func _download(_ url: URL) async throws -> URL {
		let (temp, response) = try await URLSession.shared.download(from: url)
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw PipelineError.download("HTTP \(http.statusCode)")
		}
		let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ipa")
		try FileManager.default.moveItem(at: temp, to: ipa)
		return ipa
	}

	private func _import(_ ipa: URL, provenance: SourceAppProvenance?) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			FR.handlePackageFile(ipa, sourceProvenance: provenance) { error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}
	}

	private func _newestImported(identifier: String, since: Date) -> Imported? {
		let request: NSFetchRequest<Imported> = Imported.fetchRequest()
		request.predicate = NSPredicate(format: "date >= %@", since as NSDate)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		let recent = (try? Storage.shared.context.fetch(request)) ?? []
		return recent.first { $0.identifier == identifier } ?? recent.first
	}

	/// Signs `app` the way SigningView would: recipe (or defaults), certificate slot, PPQ and the
	/// global renaming rules, preflight, then FR.signPackageFile. Deletes `replacing` afterwards.
	private func _sign(_ app: AppInfoPresentable, replacing old: AppInfoPresentable?) async throws {
		guard let cert = _selectedCertificate else { throw PipelineError.noCertificate }
		let base = OptionsManager.shared.options
		let recipe = RecipeStore.load(for: app, base: base)
		var options = recipe?.options ?? base
		let icon = recipe?.icon

		if let original = app.identifier {
			if let renamed = options.identifiers[original] { options.appIdentifier = renamed }
			if options.ppqProtection, cert.ppQCheck, options.appIdentifier == nil {
				options.appIdentifier = "\(original).\(options.ppqString)"
			}
			let kind = CertificateSlots.kind(of: cert)
			let fitted = CertificateSlots.bundleID(options.appIdentifier ?? original, for: kind)
			if fitted != (options.appIdentifier ?? original) { options.appIdentifier = fitted }
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
		if let old {
			Storage.shared.deleteApp(for: old)
		}
	}

	private func _finish(done: [String], failures: [String], verb: String, installSingle: Bool) {
		if installSingle, done.count == 1, failures.isEmpty {
			// LibraryView opens the install screen for the newest signed app
			NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: nil)
			return
		}
		var lines: [String] = []
		if !done.isEmpty {
			lines.append(String.localized("%@ apps %@. Install them from Library → Signed.", arguments: String(done.count), verb))
		}
		if !failures.isEmpty {
			lines.append(String.localized("Didn't work:") + "\n" + failures.joined(separator: "\n"))
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
