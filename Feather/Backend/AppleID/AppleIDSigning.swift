//
//  AppleIDSigning.swift
//  Accretion
//

import Foundation
import UIKit
import UserNotifications
import NimbleExtensions

// MARK: - Signing with the Apple ID
/// Accretion: when "Sign Apps with This Apple ID" is on (Settings → Apple ID), every app is signed
/// through AppleIDClient instead of a certificate: SigningHandler calls `sign` where zsign would run,
/// so Library, installs, store installs, updates and Re-sign All work as before. Each app signed this
/// way is remembered with its profile's expiry, for the reminders and Re-sign All.
enum AppleIDSigning {
	static let enabledKey = "accretion.appleid.signApps"
	static let teamKey = "accretion.appleid.teamID"
	static let udidKey = "accretion.appleid.udid"
	private static let _recordsKey = "accretion.appleid.signed"
	/// Posted when the device ID arrives from the profile
	static let udidFound = Notification.Name("Accretion.appleIDDeviceFound")

	/// On, and signed in
	static var isActive: Bool {
		UserDefaults.standard.bool(forKey: enabledKey) && AppleIDClient.session != nil
	}

	// MARK: This iPhone and the team

	/// This iPhone's device ID: the one the profile sent, or typed in, or the only device in the
	/// profile Accretion itself was installed with
	static var udid: String? {
		get {
			UserDefaults.standard.string(forKey: udidKey).flatMap(ProfileService.normalized) ?? fromOwnProfile()
		}
		set {
			UserDefaults.standard.set(newValue.flatMap(ProfileService.normalized), forKey: udidKey)
		}
	}

	/// The device in Accretion's own embedded profile, when it lists exactly one
	static func fromOwnProfile() -> String? {
		guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
		      let data = try? Data(contentsOf: url)
		else { return nil }
		return ProfileService.onlyDevice(inProfile: data)
	}

	static var teamID: String? {
		get { UserDefaults.standard.string(forKey: teamKey) }
		set { UserDefaults.standard.set(newValue, forKey: teamKey) }
	}

	private static func _team() async throws -> String {
		if let team = teamID, !team.isEmpty { return team }
		guard let team = try await AppleIDClient.teams().first else {
			throw AppleIDError(message: String.localized("This Apple ID has no developer team."))
		}
		teamID = team.id
		return team.id
	}

	// MARK: Signed apps

	struct Record: Codable, Equatable {
		/// The bundle ID as signed (with the team suffix)
		let bundleID: String
		var name: String
		/// The Library > Signed entry it belongs to
		var signedUUID: String
		var expires: Date?
		var signedAt: Date
	}

	static var records: [Record] {
		get {
			guard let data = UserDefaults.standard.data(forKey: _recordsKey) else { return [] }
			return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
		}
		set {
			UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: _recordsKey)
		}
	}

	static func isAppleIDSigned(uuid: String?) -> Bool {
		guard let uuid else { return false }
		return records.contains { $0.signedUUID == uuid }
	}

	/// Records whose Library entry still exists (the rest were deleted or re-signed)
	static func prune(keeping signedUUIDs: Set<String>) {
		records = records.filter { signedUUIDs.contains($0.signedUUID) }
	}

	/// Signs an unpacked app folder in place (SigningHandler's working copy)
	static func sign(app: URL, signedUUID: String, name: String?) async throws {
		guard AppleIDClient.session != nil else {
			throw AppleIDError(message: String.localized("Sign in with your Apple ID in Settings → Apple ID."))
		}
		guard let udid = Self.udid else {
			throw AppleIDError(message: String.localized("Accretion needs this iPhone's device ID first: Settings → Apple ID → This iPhone."))
		}
		let team = try await _team()
		let deviceName = await MainActor.run { UIDevice.current.name }
		let result = try await AppleIDClient.sign(
			app: app,
			team: team,
			udid: udid,
			deviceName: deviceName,
			removeExtensions: true
		) { prompt in
			await _ask(prompt)
		}

		let record = Record(
			bundleID: result.bundleID,
			name: name ?? result.bundleID,
			signedUUID: signedUUID,
			expires: result.profiles.compactMap(\.expires).min(),
			signedAt: Date()
		)
		var all = records.filter { $0.bundleID != record.bundleID }
		all.append(record)
		records = all
		await AppleIDReminders.schedule(for: all)
	}

	/// Only the certificate question can come up while signing; it's asked as an alert
	@MainActor
	private static func _ask(_ prompt: AppleIDPrompt) async -> AppleIDAnswer {
		guard case .revokeCertificate = prompt, let top = UIApplication.topViewController() else { return .cancel }
		return await withCheckedContinuation { continuation in
			let alert = UIAlertController(
				title: String.localized("Replace a certificate?"),
				message: String.localized("This Apple ID already has as many development certificates as Apple allows. Revoking one stops apps signed with it from opening until they are signed again."),
				preferredStyle: .alert
			)
			alert.addAction(UIAlertAction(title: String.localized("Revoke and Make a New One"), style: .destructive) { _ in
				continuation.resume(returning: .confirm)
			})
			alert.addAction(UIAlertAction(title: String.localized("Cancel"), style: .cancel) { _ in
				continuation.resume(returning: .cancel)
			})
			top.present(alert, animated: true)
		}
	}
}

// MARK: - Reminders
/// Local notifications before Apple ID-signed apps stop opening (48 h, 24 h and 2 h before, rules in
/// Core's ProfileExpiry). Nothing leaves the iPhone.
enum AppleIDReminders {
	private static let _prefix = "accretion.appleid.expiry."

	static func schedule(for records: [AppleIDSigning.Record]) async {
		let center = UNUserNotificationCenter.current()
		let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
		let pending = await center.pendingNotificationRequests()
		center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(_prefix) })
		guard granted else { return }

		let now = Date()
		for record in records {
			guard let expires = record.expires else { continue }
			for (index, date) in ProfileExpiry.reminderDates(expires: expires, now: now).enumerated() {
				let content = UNMutableNotificationContent()
				content.title = String.localized("%@ needs signing again", arguments: record.name)
				content.body = expires.timeIntervalSince(date) <= 3 * 3_600
					? String.localized("It stops opening in about 2 hours. Open Accretion → Settings → Apple ID → Re-sign All.")
					: String.localized("It stops opening in %@ days. Open Accretion → Settings → Apple ID → Re-sign All.", arguments: String(max(1, Int(expires.timeIntervalSince(date) / 86_400))))
				content.sound = .default
				let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
				let request = UNNotificationRequest(identifier: "\(_prefix)\(record.bundleID).\(index)", content: content, trigger: trigger)
				try? await center.add(request)
			}
		}
	}
}
