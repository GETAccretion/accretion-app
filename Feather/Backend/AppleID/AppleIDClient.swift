//
//  AppleIDClient.swift
//  Accretion
//

import Foundation

// MARK: - Apple ID signing
/// Accretion: free Apple ID (7-day) signing through AccretionAppleID.framework (AppleIDBridge/ in
/// this repo: Impactor's plume_core and plume_utils, the same flow as plumesign). The password goes
/// only to Apple. Session tokens and certificate keys stay in AppleIDKeychain. Nothing here is logged.

struct AppleIDTeam: Equatable {
	let id: String
	let name: String
	let type: String
	let status: String
}

struct AppleIDCertificate: Equatable {
	let name: String
	let serial: String
	let status: String
	let expires: Date?
	let machineName: String?
}

struct AppleIDProfile: Equatable {
	let bundleID: String
	let expires: Date?
}

struct AppleIDSignResult: Equatable {
	let bundleID: String
	let certificateIsNew: Bool
	let profiles: [AppleIDProfile]
}

/// What the bridge asks the user during a call
enum AppleIDPrompt: Equatable {
	struct Phone: Equatable {
		let id: Int
		let lastTwo: String
	}
	/// The code was sent to a trusted device (or by SMS); phones can receive an SMS instead
	case twoFactor(bySMS: Bool, phones: [Phone])
	/// The team has too many certificates: may one be revoked so a new one can be made?
	case revokeCertificate
}

enum AppleIDAnswer: Equatable {
	case code(String)
	case sendSMS(phoneID: Int)
	case confirm
	case cancel
}

struct AppleIDError: LocalizedError, Equatable {
	let message: String
	var errorDescription: String? { message }
}

enum AppleIDClient {
	typealias Prompter = @Sendable (AppleIDPrompt) async -> AppleIDAnswer

	/// Settings keys: the user's own anisette server, and the list read from app-config.json
	static let customAnisetteKey = "accretion.appleid.anisetteURL"
	static let remoteAnisetteKey = "accretion.appleid.anisetteServers"
	/// The certificate's machine name on Apple's side
	static let machineName = "Accretion"

	static var session: AppleIDKeychain.Session? { AppleIDKeychain.session() }

	/// Anisette servers in order (rules in Core's AnisetteServers): the user's own, ours, then the config's
	static var anisetteServers: [URL] {
		let defaults = UserDefaults.standard
		return AnisetteServers.ordered(
			custom: defaults.string(forKey: customAnisetteKey),
			remote: defaults.stringArray(forKey: remoteAnisetteKey) ?? []
		)
	}

	// MARK: Sign in

	static func signIn(email: String, password: String, prompt: @escaping Prompter) async throws {
		let answer = try await _withAnisette { anisette in
			try await _run(.login, [
				"email": email,
				"password": password,
				"anisette": anisette,
			], prompt)
		}
		guard let adsid = answer["adsid"] as? String, let token = answer["token"] as? String else {
			throw AppleIDError(message: "Apple didn't return a session.")
		}
		AppleIDKeychain.saveSession(.init(email: email, adsid: adsid, token: token))
	}

	static func signOut() {
		AppleIDKeychain.deleteSession()
	}

	// MARK: Developer services

	static func teams() async throws -> [AppleIDTeam] {
		let answer = try await _call("teams")
		let list = answer["teams"] as? [[String: Any]] ?? []
		return list.compactMap { team in
			guard let id = team["id"] as? String else { return nil }
			return AppleIDTeam(
				id: id,
				name: team["name"] as? String ?? "",
				type: team["type"] as? String ?? "",
				status: team["status"] as? String ?? ""
			)
		}
	}

	static func isDeviceRegistered(team: String, udid: String) async throws -> Bool {
		let answer = try await _call("device_status", ["team_id": team, "udid": udid])
		return answer["registered"] as? Bool ?? false
	}

	static func registerDevice(team: String, udid: String, name: String) async throws {
		_ = try await _call("register_device", ["team_id": team, "udid": udid, "device_name": name])
	}

	static func appIDs(team: String) async throws -> [String] {
		let answer = try await _call("app_ids", ["team_id": team])
		return answer["identifiers"] as? [String] ?? []
	}

	static func certificates(team: String) async throws -> [AppleIDCertificate] {
		let answer = try await _call("certificates", ["team_id": team])
		let list = answer["certificates"] as? [[String: Any]] ?? []
		return list.map { cert in
			AppleIDCertificate(
				name: cert["name"] as? String ?? "",
				serial: cert["serial"] as? String ?? "",
				status: cert["status"] as? String ?? "",
				expires: _date(cert["expires"]),
				machineName: cert["machine_name"] as? String
			)
		}
	}

	/// Signs an unpacked .app folder in place: certificate (made once per team, key kept in the
	/// Keychain), device, bundle IDs with the team suffix, App IDs, profiles, codesign. Pass a copy:
	/// the folder is changed even when signing fails. With removeExtensions, app extensions and Watch
	/// apps are deleted first (each would use one of a free account's 10 App IDs a week).
	static func sign(
		app: URL,
		team: String,
		udid: String?,
		deviceName: String,
		removeExtensions: Bool = true,
		prompt: @escaping Prompter
	) async throws -> AppleIDSignResult {
		let work = FileManager.default.temporaryDirectory
			.appendingPathComponent("AppleID-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(
			at: work,
			withIntermediateDirectories: true,
			attributes: [.protectionKey: FileProtectionType.complete]
		)
		defer { try? FileManager.default.removeItem(at: work) }

		var fields: [String: Any] = [
			"team_id": team,
			"app_path": app.path,
			"work_dir": work.path,
			"machine_name": machineName,
			"device_name": deviceName,
			"remove_extensions": removeExtensions,
		]
		if let udid { fields["udid"] = udid }
		if let key = AppleIDKeychain.key(team: team) { fields["key_pem"] = key }

		let answer = try await _call("sign", fields, prompt: prompt)
		if let key = answer["key_pem"] as? String, !key.isEmpty {
			AppleIDKeychain.saveKey(key, team: team)
		}
		let profiles = (answer["profiles"] as? [[String: Any]] ?? []).map { profile in
			AppleIDProfile(bundleID: profile["bundle_id"] as? String ?? "", expires: _date(profile["expires"]))
		}
		return AppleIDSignResult(
			bundleID: answer["bundle_id"] as? String ?? "",
			certificateIsNew: answer["certificate_new"] as? Bool ?? false,
			profiles: profiles
		)
	}

	// MARK: Bridge

	private enum _Entry {
		case login, call
	}

	/// The framework is built for iPhones only (AppleIDBridge/build-ios.sh); Simulator builds get nil
	private static func _invoke(_ entry: _Entry, _ request: UnsafePointer<CChar>, _ context: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>? {
		#if targetEnvironment(simulator)
		return nil
		#else
		switch entry {
		case .login: return accretion_appleid_login(request, _trampoline, context)
		case .call: return accretion_appleid_call(request, _trampoline, context)
		}
		#endif
	}

	private static func _release(_ answer: UnsafeMutablePointer<CChar>) {
		#if !targetEnvironment(simulator)
		accretion_appleid_free(answer)
		#endif
	}

	/// One call at a time: the bridge blocks, and calls share the anisette state files
	private static let _queue = DispatchQueue(label: "io.github.getaccretion.appleid", qos: .userInitiated)

	private static func _call(_ op: String, _ fields: [String: Any] = [:], prompt: Prompter? = nil) async throws -> [String: Any] {
		guard let session = AppleIDKeychain.session() else {
			throw AppleIDError(message: "Sign in with your Apple ID first.")
		}
		let prompter: Prompter = prompt ?? { _ in .cancel }
		return try await _withAnisette { anisette in
			var request = fields
			request["op"] = op
			request["session"] = ["adsid": session.adsid, "token": session.token]
			request["anisette"] = anisette
			return try await _run(.call, request, prompter)
		}
	}

	/// Tries each anisette server until one answers. Only anisette failures move on to the next
	/// server; they happen before anything is sent to Apple.
	private static func _withAnisette(
		_ work: ([String: Any]) async throws -> [String: Any]
	) async throws -> [String: Any] {
		var lastError: Error = AppleIDError(message: "No anisette server is set.")
		for server in anisetteServers {
			let state = try _stateFolder(for: server)
			do {
				return try await work(["url": server.absoluteString, "state_dir": state.path])
			} catch let error as AppleIDError where error.message.hasPrefix("Anisette error") {
				lastError = error
			}
		}
		throw lastError
	}

	/// The anisette device identity for one server (not the Apple ID), kept out of backups
	private static func _stateFolder(for server: URL) throws -> URL {
		let name = (server.host ?? "server") + (server.port.map { "_\($0)" } ?? "")
		let folder = URL.applicationSupportDirectory
			.appendingPathComponent("AppleID", isDirectory: true)
			.appendingPathComponent("anisette", isDirectory: true)
			.appendingPathComponent(name, isDirectory: true)
		try FileManager.default.createDirectory(
			at: folder,
			withIntermediateDirectories: true,
			attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
		)
		var excluded = folder
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		try? excluded.setResourceValues(values)
		return folder
	}

	private static func _run(_ entry: _Entry, _ request: [String: Any], _ prompt: @escaping Prompter) async throws -> [String: Any] {
		let body = try JSONSerialization.data(withJSONObject: request)
		guard let text = String(data: body, encoding: .utf8) else {
			throw AppleIDError(message: "Couldn't prepare the request.")
		}
		return try await withCheckedThrowingContinuation { continuation in
			_queue.async {
				let box = _PromptBox(prompt)
				let context = Unmanaged.passRetained(box).toOpaque()
				let raw = text.withCString { _invoke(entry, $0, context) }
				Unmanaged<_PromptBox>.fromOpaque(context).release()
				guard let raw else {
					continuation.resume(throwing: AppleIDError(message: "Apple ID signing needs an iPhone."))
					return
				}
				let answerText = String(cString: raw)
				_release(raw)

				guard let data = answerText.data(using: .utf8),
				      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
				else {
					continuation.resume(throwing: AppleIDError(message: "Apple ID signing gave an unreadable answer."))
					return
				}
				if object["ok"] as? Bool == true {
					continuation.resume(returning: object)
				} else {
					continuation.resume(throwing: AppleIDError(message: object["error"] as? String ?? "Apple ID signing failed."))
				}
			}
		}
	}

	private static let _trampoline: AccretionAppleIDPrompt = { context, request in
		guard let context else { return nil }
		let box = Unmanaged<_PromptBox>.fromOpaque(context).takeUnretainedValue()
		guard let answer = box.ask(String(cString: request)) else { return nil }
		return strdup(answer)
	}

	private static func _date(_ value: Any?) -> Date? {
		guard let text = value as? String else { return nil }
		return ISO8601DateFormatter().date(from: text)
	}
}

/// Carries the prompt into the bridge's C callback
private final class _PromptBox: @unchecked Sendable {
	private let prompt: AppleIDClient.Prompter

	init(_ prompt: @escaping AppleIDClient.Prompter) {
		self.prompt = prompt
	}

	/// Runs on the bridge's queue, which waits here for the user's answer
	func ask(_ requestJSON: String) -> String? {
		guard let data = requestJSON.data(using: .utf8),
		      let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
		      let question = AppleIDPrompt(request)
		else { return nil }
		let done = DispatchSemaphore(value: 0)
		let holder = _AnswerHolder()
		let prompt = self.prompt
		Task {
			holder.value = await prompt(question)
			done.signal()
		}
		done.wait()
		return holder.value.json
	}
}

private final class _AnswerHolder: @unchecked Sendable {
	var value: AppleIDAnswer = .cancel
}

private extension AppleIDPrompt {
	init?(_ request: [String: Any]) {
		switch request["kind"] as? String {
		case "two_factor":
			let phones = (request["phones"] as? [[String: Any]] ?? []).compactMap { phone -> Phone? in
				guard let id = phone["id"] as? Int else { return nil }
				return Phone(id: id, lastTwo: phone["last_two"] as? String ?? "")
			}
			self = .twoFactor(bySMS: request["method"] as? String == "sms", phones: phones)
		case "revoke_certificate":
			self = .revokeCertificate
		default:
			return nil
		}
	}
}

private extension AppleIDAnswer {
	var json: String {
		let object: [String: Any]
		switch self {
		case .code(let code): object = ["action": "code", "code": code]
		case .sendSMS(let id): object = ["action": "sms", "phone_id": id]
		case .confirm: object = ["action": "yes"]
		case .cancel: object = ["action": "cancel"]
		}
		guard let data = try? JSONSerialization.data(withJSONObject: object),
		      let text = String(data: data, encoding: .utf8)
		else { return #"{"action":"cancel"}"# }
		return text
	}
}
