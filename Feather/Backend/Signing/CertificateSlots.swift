//
//  CertificateSlots.swift
//  Accretion
//

import CoreData
import Foundation

// MARK: - App ID kind
/// What a provisioning profile lets you sign. Most cheap certificates are explicit: one App ID,
/// so every app signed with them gets that one bundle ID and replaces the previous one on the device.
enum AppIDKind: Equatable {
	/// `TEAM.*` (prefix "") or `TEAM.com.example.*` (prefix "com.example.")
	case wildcard(prefix: String)
	/// `TEAM.com.example.app`: exactly one bundle ID
	case explicit(String)
}

extension Certificate {
	/// The profile's App ID without the team prefix: "*", "com.example.*" or "com.example.app".
	var accretionAppID: String? {
		guard let raw = Entitlements?["application-identifier"]?.value as? String else { return nil }
		let parts = raw.split(separator: ".", maxSplits: 1)
		return parts.count == 2 ? String(parts[1]) : raw
	}

	var accretionAppIDKind: AppIDKind? {
		guard let id = accretionAppID, !id.isEmpty else { return nil }
		if id == "*" { return .wildcard(prefix: "") }
		if id.hasSuffix(".*") { return .wildcard(prefix: String(id.dropLast())) }
		return .explicit(id)
	}
}

// MARK: - Slots
enum CertificateSlots {
	/// The App ID kind of a stored certificate, read from its .mobileprovision.
	static func kind(of cert: CertificatePair?) -> AppIDKind? {
		guard let cert else { return nil }
		return Storage.shared.getProvisionFileDecoded(for: cert)?.accretionAppIDKind
	}

	/// The bundle ID an app must use to be signed with this certificate:
	/// - explicit App ID: always that ID
	/// - prefix wildcard: the wanted ID if it fits, otherwise the prefix plus the wanted ID
	/// - full wildcard or unknown: the wanted ID unchanged
	static func bundleID(_ wanted: String, for kind: AppIDKind?) -> String {
		switch kind {
		case .explicit(let id):
			return id
		case .wildcard(let prefix) where !prefix.isEmpty && !wanted.hasPrefix(prefix):
			return prefix + wanted
		default:
			return wanted
		}
	}

	/// For an explicit App ID: the app signed most recently into that one slot, which the next
	/// install will replace on the device.
	static func occupant(of cert: CertificatePair?) -> Signed? {
		guard case .explicit(let id) = kind(of: cert) else { return nil }
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		request.predicate = NSPredicate(format: "identifier == %@", id)
		request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
		request.fetchLimit = 1
		return (try? Storage.shared.context.fetch(request))?.first
	}
}
