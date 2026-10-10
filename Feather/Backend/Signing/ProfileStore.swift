//
//  ProfileStore.swift
//  Accretion
//

import Foundation

// MARK: - Profiles per certificate
/// A certificate normally comes with one provisioning profile. Sellers whose profiles each cover a
/// single App ID often give one profile per app; adding them all here gives every app its own
/// slot, so several apps stay installed and each one updates in place.
///
/// Extra profiles live in Certificates/<uuid>/ExtraProfiles, next to an assignments file that
/// remembers which app uses which profile.
enum ProfileStore {
	struct Profile: Identifiable {
		let url: URL
		let decoded: Certificate
		let isMain: Bool
		var id: String { url.lastPathComponent }
		var kind: AppIDKind? { decoded.accretionAppIDKind }
	}

	// MARK: Listing
	static func profiles(for cert: CertificatePair) -> [Profile] {
		var list: [Profile] = []
		if let main = Storage.shared.getFile(.provision, from: cert, allowOverride: false),
		   let decoded = CertificateReader(main).decoded {
			list.append(Profile(url: main, decoded: decoded, isMain: true))
		}
		for url in _extraFiles(for: cert) {
			if let decoded = CertificateReader(url).decoded {
				list.append(Profile(url: url, decoded: decoded, isMain: false))
			}
		}
		return list
	}

	// MARK: Adding and removing
	/// Copies profiles in. Each must belong to the certificate's team; returns one message per
	/// file that was refused.
	static func add(_ urls: [URL], to cert: CertificatePair) -> [String] {
		guard let folder = _folder(for: cert) else { return [String.localized("This certificate has no folder.")] }
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let team = profiles(for: cert).first(where: \.isMain)?.decoded.TeamIdentifier.first
		var refused: [String] = []

		for url in urls {
			let scoped = url.startAccessingSecurityScopedResource()
			defer { if scoped { url.stopAccessingSecurityScopedResource() } }
			guard let decoded = CertificateReader(url).decoded else {
				refused.append(String.localized("%@ isn't a provisioning profile.", arguments: url.lastPathComponent))
				continue
			}
			if let team, decoded.TeamIdentifier.first != team {
				refused.append(String.localized("%@ is for team %@, but this certificate is team %@.", arguments: url.lastPathComponent, decoded.TeamIdentifier.first ?? "?", team))
				continue
			}
			let destination = folder.appendingPathComponent("\(decoded.UUID).mobileprovision")
			try? FileManager.default.removeItem(at: destination)
			if (try? FileManager.default.copyItem(at: url, to: destination)) == nil {
				refused.append(String.localized("Couldn't copy %@.", arguments: url.lastPathComponent))
			}
		}
		return refused
	}

	static func remove(_ profile: Profile, from cert: CertificatePair) {
		guard !profile.isMain else { return }
		try? FileManager.default.removeItem(at: profile.url)
		var assignments = _assignments(for: cert)
		assignments = assignments.filter { $0.value != profile.id }
		_saveAssignments(assignments, for: cert)
	}

	// MARK: Choosing
	struct Choice {
		let profile: Profile
		/// The app this profile already belongs to, when signing will take its slot
		let replaces: String?
	}

	/// The profile to sign `appKey` (an app's original bundle ID) with. Assigns a free profile
	/// the first time, so the same app always gets the same profile and bundle ID.
	static func choose(for appKey: String, cert: CertificatePair, assign: Bool) -> Choice? {
		let all = profiles(for: cert)
		guard let main = all.first(where: \.isMain) else { return nil }

		// a wildcard covers every app without taking a slot
		if let wildcard = all.first(where: { if case .wildcard = $0.kind { return true } else { return false } }) {
			return Choice(profile: wildcard, replaces: nil)
		}

		var assignments = _assignments(for: cert)
		if let assigned = assignments[appKey], let profile = all.first(where: { $0.id == assigned }) {
			return Choice(profile: profile, replaces: nil)
		}

		let taken = Set(assignments.values)
		if let free = all.first(where: { !taken.contains($0.id) }) {
			if assign {
				assignments[appKey] = free.id
				_saveAssignments(assignments, for: cert)
			}
			return Choice(profile: free, replaces: nil)
		}

		// every slot is taken: share the main profile's slot with whoever has it
		let holder = assignments.first(where: { $0.value == main.id })?.key
		return Choice(profile: main, replaces: holder == appKey ? nil : holder)
	}

	/// Which app each profile is assigned to, by profile file name.
	static func assignedApps(for cert: CertificatePair) -> [String: String] {
		Dictionary(_assignments(for: cert).map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
	}

	// MARK: Private
	private static func _folder(for cert: CertificatePair) -> URL? {
		Storage.shared.getUuidDirectory(for: cert)?.appendingPathComponent("ExtraProfiles")
	}

	private static func _extraFiles(for cert: CertificatePair) -> [URL] {
		guard let folder = _folder(for: cert) else { return [] }
		return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
			.filter { $0.pathExtension == "mobileprovision" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
	}

	private static func _assignmentsFile(for cert: CertificatePair) -> URL? {
		_folder(for: cert)?.appendingPathComponent("assignments.json")
	}

	private static func _assignments(for cert: CertificatePair) -> [String: String] {
		guard let file = _assignmentsFile(for: cert), let data = try? Data(contentsOf: file) else { return [:] }
		return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
	}

	private static func _saveAssignments(_ assignments: [String: String], for cert: CertificatePair) {
		guard let folder = _folder(for: cert), let file = _assignmentsFile(for: cert) else { return }
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		if let data = try? JSONEncoder().encode(assignments) {
			try? data.write(to: file, options: .atomic)
		}
	}
}

// MARK: - Override while signing
/// While one app is being signed, `Storage.getFile(.provision, from:)` returns the profile chosen
/// for that app, so the signer and the entitlements merge both use it. Signing runs one app at a
/// time; the lock only guards against reads from the signing task's thread.
enum ProfileOverride {
	private static let _lock = NSLock()
	private static var _overrides: [String: URL] = [:]

	static func set(_ url: URL?, for cert: CertificatePair?) {
		guard let uuid = cert?.uuid else { return }
		_lock.lock(); defer { _lock.unlock() }
		_overrides[uuid] = url
	}

	static func url(for cert: CertificatePair) -> URL? {
		guard let uuid = cert.uuid else { return nil }
		_lock.lock(); defer { _lock.unlock() }
		return _overrides[uuid]
	}
}
