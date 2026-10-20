//
//  CertificateSlots.swift
//  Accretion
//

import CoreData
import Foundation

// MARK: - App ID kind
// AppIDKind and the bundle ID rule live in Backend/Core/AppIDFit.swift (tested in CoreTests).
extension Certificate {
	/// The profile's App ID without the team prefix: "*", "com.example.*" or "com.example.app".
	var accretionAppID: String? {
		guard let raw = Entitlements?["application-identifier"]?.value as? String else { return nil }
		let parts = raw.split(separator: ".", maxSplits: 1)
		return parts.count == 2 ? String(parts[1]) : raw
	}

	var accretionAppIDKind: AppIDKind? { AppIDKind(appID: accretionAppID) }
}

// MARK: - Slots
enum CertificateSlots {
	/// Settings → Certificates: with a single-app certificate, keep each app's own bundle ID
	/// (default, several apps fit) or rename every app to the certificate's one App ID (one slot)
	static let keepOwnIDKey = "accretion.signing.keepBundleID"

	static var keepsOwnID: Bool {
		UserDefaults.standard.object(forKey: keepOwnIDKey) as? Bool ?? true
	}

	/// The App ID kind of a stored certificate, read from its .mobileprovision.
	static func kind(of cert: CertificatePair?) -> AppIDKind? {
		guard let cert else { return nil }
		return Storage.shared.getProvisionFileDecoded(for: cert)?.accretionAppIDKind
	}

	/// The bundle ID an app is signed with under this certificate (AppIDFit, with the setting above)
	static func bundleID(_ wanted: String, for kind: AppIDKind?) -> String {
		AppIDFit.bundleID(wanted, for: kind, keepOwnID: keepsOwnID)
	}

	/// For an explicit App ID with the rename option on: the app signed most recently into that one
	/// slot, which the next install will replace on the device. Nil while apps keep their own IDs.
	static func occupant(of cert: CertificatePair?) -> Signed? {
		guard !keepsOwnID, case .explicit(let id) = kind(of: cert) else { return nil }
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.predicate = NSPredicate(format: "identifier == %@", id)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return (try? Storage.shared.context.fetch(request))?.first
	}
}
