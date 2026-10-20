//
//  AppleIDKeychain.swift
//  Accretion
//

import Foundation
import Security

// MARK: - Apple ID secrets
/// Accretion: what Apple ID signing keeps, all in the Keychain on this device only (never backed up
/// or synced): the session tokens Apple returns after sign-in, and each team's certificate key.
/// The Apple ID password is never stored.
enum AppleIDKeychain {
	struct Session: Codable, Equatable {
		let email: String
		let adsid: String
		let token: String
	}

	private static let service = "io.github.getaccretion.appleid"
	private static let sessionAccount = "session"
	private static func _keyAccount(_ team: String) -> String { "key." + team }

	static func session() -> Session? {
		guard let data = _read(sessionAccount) else { return nil }
		return try? JSONDecoder().decode(Session.self, from: data)
	}

	static func saveSession(_ session: Session) {
		guard let data = try? JSONEncoder().encode(session) else { return }
		_write(sessionAccount, data)
	}

	/// Signing out forgets the tokens; certificate keys stay, so signing in again reuses the certificate
	static func deleteSession() {
		_delete(sessionAccount)
	}

	static func key(team: String) -> String? {
		_read(_keyAccount(team)).flatMap { String(data: $0, encoding: .utf8) }
	}

	static func saveKey(_ pem: String, team: String) {
		_write(_keyAccount(team), Data(pem.utf8))
	}

	/// Everything: tokens and every certificate key
	static func deleteAll() {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
		]
		SecItemDelete(query as CFDictionary)
	}

	private static func _query(_ account: String) -> [String: Any] {
		[
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
	}

	private static func _read(_ account: String) -> Data? {
		var query = _query(account)
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
		return result as? Data
	}

	private static func _write(_ account: String, _ data: Data) {
		_delete(account)
		var item = _query(account)
		item[kSecValueData as String] = data
		item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		SecItemAdd(item as CFDictionary, nil)
	}

	private static func _delete(_ account: String) {
		SecItemDelete(_query(account) as CFDictionary)
	}
}
