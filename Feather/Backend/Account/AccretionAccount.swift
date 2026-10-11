//
//  AccretionAccount.swift
//  Accretion
//

import AuthenticationServices
import CommonCrypto
import CryptoKit
import Foundation
import Security
import UIKit

// MARK: - Account
/// The Accretion account (the web store's community login, on Supabase), used here to back up
/// certificates. Talks to Supabase's REST API directly; the project address and public anon key
/// come from the store's own config.js, so the app and the website always use the same project.
@MainActor
final class AccretionAccount: ObservableObject {
	static let shared = AccretionAccount()

	@Published private(set) var email: String?
	/// The signed-in user's id, for the community tables' `user_id` columns
	private(set) var userID: String?
	var isSignedIn: Bool { email != nil }

	struct Backup: Decodable, Identifiable {
		let id: String
		let label: String
		let expires: String?
		let payload: String
		let salt: String
		let rounds: Int
		let created_at: String
	}

	enum AccountError: LocalizedError {
		case notConfigured, notSignedIn, server(String), wrongPassphrase
		var errorDescription: String? {
			switch self {
			case .notConfigured: return String.localized("Couldn't reach the Accretion account service.")
			case .notSignedIn: return String.localized("Sign in to your Accretion account first.")
			case .server(let message): return message
			case .wrongPassphrase: return String.localized("That passphrase doesn't open this backup.")
			}
		}
	}

	private var _config: (url: URL, key: String)?
	private var _accessToken: String?
	private var _expiresAt: Date = .distantPast

	private init() {
		email = _Keychain.read("email")
		userID = _Keychain.read("uid")
	}

	// MARK: Config
	/// Reads `window.ACCRETION_CONFIG = {...}` from the store's config.js.
	private func _configuration() async throws -> (url: URL, key: String) {
		if let config = _config { return config }
		let source = URL(string: "https://getaccretion.github.io/config.js")!
		guard
			let response = try? await URLSession.shared.data(from: source),
			let text = String(data: response.0, encoding: .utf8),
			let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
			let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: String],
			let url = json["supabaseUrl"].flatMap(URL.init(string:)),
			let key = json["supabaseKey"]
		else {
			throw AccountError.notConfigured
		}
		_config = (url, key)
		return (url, key)
	}

	// MARK: Sign in / out
	func signIn(email: String, password: String) async throws {
		try await _token(["email": email, "password": password], grant: "password")
		self.email = email
		_Keychain.write(email, for: "email")
	}

	// MARK: Google, GitHub, Discord
	/// The web store's "Continue with …" providers. The page opens in a private sign-in sheet and
	/// returns to accretion://auth-callback with a one-time code, swapped for a session (PKCE).
	enum Provider: String, CaseIterable, Identifiable {
		case google, github, discord
		var id: String { rawValue }
		var title: String {
			switch self {
			case .google: return "Google"
			case .github: return "GitHub"
			case .discord: return "Discord"
			}
		}
	}

	/// Providers switched on in the Supabase project (the same check the website does)
	func enabledProviders() async -> [Provider] {
		guard let config = try? await _configuration() else { return [] }
		var request = URLRequest(url: config.url.appendingPathComponent("auth/v1/settings"))
		request.setValue(config.key, forHTTPHeaderField: "apikey")
		guard
			let (data, _) = try? await URLSession.shared.data(for: request),
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let external = json["external"] as? [String: Any]
		else {
			return []
		}
		return Provider.allCases.filter { external[$0.rawValue] as? Bool == true }
	}

	func signIn(with provider: Provider) async throws {
		let config = try await _configuration()
		var bytes = [UInt8](repeating: 0, count: 32)
		_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
		let verifier = Self._base64URL(Data(bytes))
		let challenge = Self._base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

		var authorize = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
		authorize.queryItems = [
			URLQueryItem(name: "provider", value: provider.rawValue),
			URLQueryItem(name: "redirect_to", value: "accretion://auth-callback"),
			URLQueryItem(name: "code_challenge", value: challenge),
			URLQueryItem(name: "code_challenge_method", value: "s256"),
		]
		let callback = try await _WebSignIn.run(authorize.url!, scheme: "accretion")
		// Supabase puts the code in the query, and errors sometimes in the fragment
		let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
		var fragment = URLComponents()
		fragment.query = components?.fragment
		let items = (components?.queryItems ?? []) + (fragment.queryItems ?? [])
		guard let code = items.first(where: { $0.name == "code" })?.value else {
			let reason = items.first(where: { $0.name == "error_description" })?.value
			throw AccountError.server(reason ?? String.localized("Sign-in was cancelled."))
		}
		let user = try await _token(["auth_code": code, "code_verifier": verifier], grant: "pkce")
		let email = (user?["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? provider.title
		self.email = email
		_Keychain.write(email, for: "email")
	}

	private static func _base64URL(_ data: Data) -> String {
		data.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")
	}

	func signOut() {
		_downloadKey = nil
		userID = nil
		_Keychain.delete("uid")
		email = nil
		_accessToken = nil
		_expiresAt = .distantPast
		_Keychain.delete("email")
		_Keychain.delete("refresh")
	}

	/// Returns the signed-in user object from the response.
	@discardableResult
	private func _token(_ body: [String: String], grant: String) async throws -> [String: Any]? {
		let config = try await _configuration()
		var request = URLRequest(url: config.url.appendingPathComponent("auth/v1/token"))
		request.url = URL(string: request.url!.absoluteString + "?grant_type=\(grant)")
		request.httpMethod = "POST"
		request.setValue(config.key, forHTTPHeaderField: "apikey")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONSerialization.data(withJSONObject: body)

		let (data, response) = try await URLSession.shared.data(for: request)
		let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
		guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
			let message = json["error_description"] as? String ?? json["msg"] as? String ?? String.localized("Sign-in failed.")
			throw AccountError.server(message)
		}
		_accessToken = access
		_expiresAt = Date().addingTimeInterval(TimeInterval((json["expires_in"] as? Int) ?? 3600) - 60)
		if let refresh = json["refresh_token"] as? String { _Keychain.write(refresh, for: "refresh") }
		let user = json["user"] as? [String: Any]
		if let id = user?["id"] as? String {
			userID = id
			_Keychain.write(id, for: "uid")
		}
		return user
	}

	/// A valid access token, refreshed with the saved refresh token when needed.
	/// One refresh at a time: Supabase can revoke a session when the same refresh token is used twice.
	private var _refreshing: Task<Void, Error>?

	private func _bearer() async throws -> String {
		if let token = _accessToken, Date() < _expiresAt { return token }
		if let pending = _refreshing {
			try await pending.value
		} else {
			guard isSignedIn, let refresh = _Keychain.read("refresh") else { throw AccountError.notSignedIn }
			let task = Task { _ = try await self._token(["refresh_token": refresh], grant: "refresh_token") }
			_refreshing = task
			defer { _refreshing = nil }
			do {
				try await task.value
			} catch AccountError.server {
				// the server turned the session down (expired or revoked): sign out cleanly
				signOut()
				throw AccountError.notSignedIn
			}
		}
		guard let token = _accessToken else { throw AccountError.notSignedIn }
		return token
	}

	// MARK: Table
	/// `anonymous` reads public tables (stats, comments) without an account.
	private func _rest(_ path: String, method: String = "GET", body: Any? = nil, prefer: String? = nil, anonymous: Bool = false) async throws -> Data {
		let config = try await _configuration()
		var request = URLRequest(url: URL(string: config.url.absoluteString + "/rest/v1/" + path)!)
		request.httpMethod = method
		request.setValue(config.key, forHTTPHeaderField: "apikey")
		let token: String
		if anonymous {
			// public reads still work when the session can't be refreshed
			var session: String?
			if isSignedIn { session = try? await _bearer() }
			token = session ?? config.key
		} else {
			token = try await _bearer()
		}
		request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
		if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
			let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
			throw AccountError.server(json["message"] as? String ?? String.localized("The account service refused the request."))
		}
		return data
	}

	func backups() async throws -> [Backup] {
		let data = try await _rest("certificate_backups?select=*&order=created_at.desc")
		return try JSONDecoder().decode([Backup].self, from: data)
	}

	func deleteBackup(_ id: String) async throws {
		_ = try await _rest("certificate_backups?id=eq.\(id)", method: "DELETE")
	}

	// MARK: Community (the web store's likes, ratings and comments)
	struct AppSocial {
		var likes = 0
		var ratings = 0
		var average: Double?
		var comments = 0
		var liked = false
		var stars = 0
	}

	struct Post: Decodable, Identifiable {
		let id: Int
		let parent_id: Int?
		let body: String
		let created_at: String
		let username: String
		let display_name: String?
		let color: String?
		let role: String?
		let likes: Int?
		let replies: Int?
		let author: String?
		let hidden: Bool?
		let edited_at: String?
		let supporter: Bool?
	}

	private static func _quoted(_ value: String) -> String {
		value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_"))) ?? value
	}

	func appSocial(_ appID: String) async throws -> AppSocial {
		let id = Self._quoted(appID)
		var social = AppSocial()
		let statsData = try await _rest("app_stats?select=*&app_id=eq.\(id)", anonymous: true)
		if let row = ((try? JSONSerialization.jsonObject(with: statsData)) as? [[String: Any]])?.first {
			social.likes = row["likes"] as? Int ?? 0
			social.ratings = row["ratings"] as? Int ?? 0
			social.comments = row["comments"] as? Int ?? 0
			social.average = (row["avg_rating"] as? Double) ?? (row["avg_rating"] as? String).flatMap(Double.init)
		}
		if isSignedIn, let uid = try? await _uid() {
			let liked = try await _rest("app_likes?select=app_id&app_id=eq.\(id)&user_id=eq.\(uid)")
			social.liked = !(((try? JSONSerialization.jsonObject(with: liked)) as? [Any]) ?? []).isEmpty
			let rated = try await _rest("app_ratings?select=stars&app_id=eq.\(id)&user_id=eq.\(uid)")
			social.stars = (((try? JSONSerialization.jsonObject(with: rated)) as? [[String: Any]])?.first?["stars"] as? Int) ?? 0
		}
		return social
	}

	/// The user id, refreshing the session first when it isn't known yet (sign-ins from 1.0.0)
	private func _uid() async throws -> String {
		if userID == nil { _ = try await _bearer() }
		guard let uid = userID else { throw AccountError.notSignedIn }
		return uid
	}

	func likeApp(_ appID: String, _ on: Bool) async throws {
		let uid = try await _uid()
		if on {
			_ = try await _rest("app_likes", method: "POST", body: ["app_id": appID], prefer: "return=minimal")
		} else {
			_ = try await _rest("app_likes?app_id=eq.\(Self._quoted(appID))&user_id=eq.\(uid)", method: "DELETE")
		}
	}

	func rateApp(_ appID: String, stars: Int) async throws {
		let uid = try await _uid()
		_ = try await _rest(
			"app_ratings",
			method: "POST",
			body: ["app_id": appID, "user_id": uid, "stars": stars],
			prefer: "resolution=merge-duplicates,return=minimal"
		)
	}

	func thread(_ appID: String) async throws -> [Post] {
		let columns = "id,parent_id,body,created_at,username,display_name,color,role,likes,replies,author,hidden,edited_at,supporter"
		let data = try await _rest("post_feed?select=\(columns)&app_id=eq.\(Self._quoted(appID))&order=created_at.asc&limit=500", anonymous: true)
		return try JSONDecoder().decode([Post].self, from: data)
	}

	/// Every app's likes, ratings and comments (public), for Discover's community shelves
	func allAppStats() async -> [(app: String, likes: Int, ratings: Int, average: Double, comments: Int)] {
		guard
			let data = try? await _rest("app_stats?select=*&limit=5000", anonymous: true),
			let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
		else { return [] }
		return rows.compactMap { row in
			guard let app = row["app_id"] as? String else { return nil }
			let average = (row["avg_rating"] as? Double) ?? (row["avg_rating"] as? String).flatMap(Double.init) ?? 0
			return (app, row["likes"] as? Int ?? 0, row["ratings"] as? Int ?? 0, average, row["comments"] as? Int ?? 0)
		}
	}

	/// Unread notifications (likes, replies, follows), for the bell; RLS shows only your own
	func unreadNotifications() async -> Int {
		guard isSignedIn,
			  let data = try? await _rest("notifications?select=id&read=eq.false&limit=100"),
			  let rows = try? JSONSerialization.jsonObject(with: data) as? [Any]
		else { return 0 }
		return rows.count
	}

	/// Your role on the store ("user", "mod", "admin"), for the moderator Hide action
	func myRole() async -> String? {
		guard isSignedIn, let uid = try? await _uid(),
			  let data = try? await _rest("profiles?select=role&id=eq.\(uid)"),
			  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
		else { return nil }
		return rows.first?["role"] as? String
	}

	/// Which of these posts you've liked
	func likedPosts(_ ids: [Int]) async -> Set<Int> {
		guard isSignedIn, !ids.isEmpty, let uid = try? await _uid() else { return [] }
		let list = ids.map(String.init).joined(separator: ",")
		guard
			let data = try? await _rest("post_likes?select=post_id&user_id=eq.\(uid)&post_id=in.(\(list))"),
			let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
		else { return [] }
		return Set(rows.compactMap { $0["post_id"] as? Int })
	}

	func likePost(_ id: Int, _ on: Bool) async throws {
		let uid = try await _uid()
		if on {
			_ = try await _rest("post_likes", method: "POST", body: ["post_id": id], prefer: "return=minimal")
		} else {
			_ = try await _rest("post_likes?post_id=eq.\(id)&user_id=eq.\(uid)", method: "DELETE")
		}
	}

	func deletePost(_ id: Int) async throws {
		_ = try await _rest("posts?id=eq.\(id)", method: "DELETE")
	}

	/// Moderators: hide or show a post (row level security only lets mods do this)
	func hidePost(_ id: Int, _ hidden: Bool) async throws {
		_ = try await _rest("posts?id=eq.\(id)", method: "PATCH", body: ["hidden": hidden], prefer: "return=minimal")
	}

	func report(post id: Int, reason: String) async throws {
		_ = try await _rest("reports", method: "POST", body: ["post_id": id, "reason": reason], prefer: "return=minimal")
	}

	func comment(on appID: String, body: String, replyTo parent: Int? = nil) async throws {
		var row: [String: Any] = ["body": body, "app_id": appID]
		if let parent { row["parent_id"] = parent }
		_ = try await _rest("posts", method: "POST", body: row, prefer: "return=minimal")
	}

	// MARK: Store counts
	/// The website's anonymous view and install counts, which feed "Most popular" (public.track:
	/// once per visitor per app per day, no account or IP stored). Fire and forget.
	nonisolated func track(_ kind: String, app bundleID: String) {
		Task { @MainActor in
			_ = try? await _rest("rpc/track", method: "POST", body: ["p_kind": kind, "p_app": bundleID], anonymous: true)
		}
	}

	// MARK: Downloads
	private var _downloadKey: String?

	/// Accretion's own builds (Accretion Mods, the Accretion app) live on the store's download
	/// server, which hands them only to account holders. For those apps this returns the server
	/// link with the user's personal key; every other app keeps `url`.
	func downloadURL(for bundleID: String, fallback url: URL) async -> URL {
		guard isSignedIn else { return Self.tagged(url) }
		do {
			let config = try await _configuration()
			guard try await _hostedBundleIDs().contains(bundleID) else { return url }
			if _downloadKey == nil {
				let keyData = try await _rest("rpc/my_download_key", method: "POST", body: ["rotate": false])
				_downloadKey = try JSONDecoder().decode(String.self, from: keyData)
			}
			guard let key = _downloadKey else { return url }
			var link = URLComponents(url: config.url.appendingPathComponent("functions/v1/download"), resolvingAgainstBaseURL: false)!
			link.queryItems = [URLQueryItem(name: "app", value: bundleID), URLQueryItem(name: "key", value: key)]
			return Self.tagged(link.url ?? url)
		} catch {
			return Self.tagged(url)
		}
	}

	/// Adds this app's version to download-server links. The server refuses Accretion requests
	/// without it (versions before 1.0.5) and versions below the store's minimum.
	nonisolated static func tagged(_ url: URL) -> URL {
		guard
			url.path.hasSuffix("/functions/v1/download"),
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			!(components.queryItems ?? []).contains(where: { $0.name == "av" })
		else {
			return url
		}
		let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
		components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "av", value: version)]
		return components.url ?? url
	}

	/// Which apps the download server hosts, fetched once every 10 minutes (the website does the
	/// same) instead of on every install.
	private var _hosted: (ids: Set<String>, at: Date)?

	private func _hostedBundleIDs() async throws -> Set<String> {
		if let hosted = _hosted, Date().timeIntervalSince(hosted.at) < 600 { return hosted.ids }
		let data = try await _rest("hosted_builds?select=bundle_id", anonymous: true)
		let rows = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
		let ids = Set(rows.compactMap { $0["bundle_id"] as? String })
		_hosted = (ids, Date())
		return ids
	}

	/// The SHA-256 recorded when one of Accretion's own builds was published, for a download-server
	/// link (the version in the link, or the newest; Accretion itself is always the newest). nil
	/// for other links and for builds published before fingerprints existed.
	func expectedSHA256(for url: URL, bundleID: String) async -> String? {
		guard url.path.hasSuffix("/functions/v1/download"),
			  let data = try? await _rest("hosted_builds?select=version,sha256&bundle_id=eq.\(Self._quoted(bundleID))", anonymous: true),
			  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
		else { return nil }
		let builds = rows.compactMap { row -> (version: String, sha: String?)? in
			guard let version = row["version"] as? String else { return nil }
			return (version, row["sha256"] as? String)
		}
		let wanted = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "version" }?.value
		let pick = wanted.flatMap { version in bundleID == "io.github.getaccretion.Accretion" ? nil : builds.first { $0.version == version } }
			?? builds.max { UpdateManager.isVersion($1.version, newerThan: $0.version) }
		return pick?.sha
	}

	/// Forget the personal key, e.g. after the server refused it because it was replaced on the website
	func forgetDownloadKey() {
		_downloadKey = nil
	}

	// MARK: Back up and restore
	/// Seals every certificate on this device with the passphrase and uploads one row each.
	/// Returns how many were backed up.
	func backUp(_ certificates: [CertificatePair], passphrase: String) async throws -> Int {
		var count = 0
		for cert in certificates {
			guard
				let p12 = Storage.shared.getFile(.certificate, from: cert, allowOverride: false).flatMap({ try? Data(contentsOf: $0) }),
				let profile = Storage.shared.getFile(.provision, from: cert, allowOverride: false).flatMap({ try? Data(contentsOf: $0) })
			else {
				continue
			}
			let plain = try JSONSerialization.data(withJSONObject: [
				"p12": p12.base64EncodedString(),
				"mobileprovision": profile.base64EncodedString(),
				"password": cert.password ?? "",
				"nickname": cert.nickname ?? "",
			])
			let sealed = try CertificateSeal.seal(plain, passphrase: passphrase)
			var row: [String: Any] = [
				"label": String((cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? "Certificate").prefix(80)),
				"payload": sealed.payload,
				"salt": sealed.salt,
				"rounds": sealed.rounds,
			]
			if let expiration = cert.expiration { row["expires"] = ISO8601DateFormatter().string(from: expiration) }
			_ = try await _rest("certificate_backups", method: "POST", body: row)
			count += 1
		}
		return count
	}

	/// Opens a backup with the passphrase and imports it like a certificate added by hand.
	func restore(_ backup: Backup, passphrase: String) async throws {
		guard
			let plain = CertificateSeal.open(backup.payload, salt: backup.salt, rounds: backup.rounds, passphrase: passphrase),
			let json = try? JSONSerialization.jsonObject(with: plain) as? [String: String],
			let p12 = json["p12"].flatMap({ Data(base64Encoded: $0) }),
			let profile = json["mobileprovision"].flatMap({ Data(base64Encoded: $0) })
		else {
			throw AccountError.wrongPassphrase
		}
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AccretionRestore_\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let p12URL = folder.appendingPathComponent("cert.p12")
		let profileURL = folder.appendingPathComponent("cert.mobileprovision")
		try p12.write(to: p12URL)
		try profile.write(to: profileURL)
		defer { try? FileManager.default.removeItem(at: folder) }

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			FR.handleCertificateFiles(
				p12URL: p12URL,
				provisionURL: profileURL,
				p12Password: json["password"] ?? "",
				certificateName: json["nickname"] ?? ""
			) { error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}
	}
}

// MARK: - Web sign-in sheet
/// ASWebAuthenticationSession wrapped for async/await. Uses a private session so the provider's
/// cookies don't leak between accounts.
private final class _WebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
	@MainActor private static var _current: _WebSignIn?
	private let _anchor: ASPresentationAnchor
	private var _session: ASWebAuthenticationSession?

	private init(anchor: ASPresentationAnchor) {
		_anchor = anchor
	}

	@MainActor
	static func run(_ url: URL, scheme: String) async throws -> URL {
		let window = UIApplication.shared.connectedScenes
			.compactMap { ($0 as? UIWindowScene)?.keyWindow }
			.first ?? UIWindow()
		let runner = _WebSignIn(anchor: window)
		_current = runner
		defer { _current = nil }
		return try await withCheckedThrowingContinuation { continuation in
			let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
				if let callback {
					continuation.resume(returning: callback)
				} else {
					continuation.resume(throwing: error ?? AccretionAccount.AccountError.server(String.localized("Sign-in was cancelled.")))
				}
			}
			session.presentationContextProvider = runner
			session.prefersEphemeralWebBrowserSession = true
			runner._session = session
			if !session.start() {
				continuation.resume(throwing: AccretionAccount.AccountError.server(String.localized("Couldn't open the sign-in page. Try again.")))
			}
		}
	}

	func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		_anchor
	}
}

// MARK: - Sealing
/// AES-GCM with a 256-bit key from PBKDF2-SHA256 over the passphrase and a random salt.
enum CertificateSeal {
	/// OWASP's current guidance for PBKDF2-HMAC-SHA256. Backups made by 1.0.0–1.0.6 used 210,000
	/// and still open: the round count is stored with each backup.
	static let defaultRounds = 600_000
	/// What open() accepts from a stored backup, so a tampered row can't force a weak or huge count
	static let acceptedRounds = 100_000...10_000_000

	static func seal(_ data: Data, passphrase: String, rounds: Int = defaultRounds) throws -> (payload: String, salt: String, rounds: Int) {
		var salt = Data(count: 16)
		let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
		guard status == errSecSuccess else { throw AccretionAccount.AccountError.server(String.localized("Couldn't secure the backup.")) }
		guard let key = _key(passphrase, salt: salt, rounds: rounds),
			  let combined = try AES.GCM.seal(data, using: key).combined
		else {
			throw AccretionAccount.AccountError.server(String.localized("Couldn't secure the backup."))
		}
		return (combined.base64EncodedString(), salt.base64EncodedString(), rounds)
	}

	static func open(_ payload: String, salt: String, rounds: Int, passphrase: String) -> Data? {
		guard
			acceptedRounds.contains(rounds),
			let combined = Data(base64Encoded: payload),
			let saltData = Data(base64Encoded: salt), saltData.count >= 16,
			let box = try? AES.GCM.SealedBox(combined: combined),
			let key = _key(passphrase, salt: saltData, rounds: rounds)
		else {
			return nil
		}
		return try? AES.GCM.open(box, using: key)
	}

	/// nil when derivation fails, so a failure can never silently become an all-zero key
	private static func _key(_ passphrase: String, salt: Data, rounds: Int) -> SymmetricKey? {
		guard rounds > 0, rounds <= Int(UInt32.max), !salt.isEmpty else { return nil }
		var derived = Data(count: 32)
		let password = Array(passphrase.utf8)
		let status = derived.withUnsafeMutableBytes { out in
			salt.withUnsafeBytes { saltBytes in
				CCKeyDerivationPBKDF(
					CCPBKDFAlgorithm(kCCPBKDF2),
					password.map { Int8(bitPattern: $0) }, password.count,
					saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
					CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds),
					out.bindMemory(to: UInt8.self).baseAddress, 32
				)
			}
		}
		guard status == kCCSuccess else { return nil }
		return SymmetricKey(data: derived)
	}
}

// MARK: - Keychain
/// The account email and refresh token, kept in the Keychain, never in UserDefaults.
private enum _Keychain {
	private static let service = "io.github.getaccretion.account"

	static func write(_ value: String, for account: String) {
		delete(account)
		SecItemAdd([
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: Data(value.utf8),
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
		] as [String: Any] as CFDictionary, nil)
	}

	static func read(_ account: String) -> String? {
		var result: AnyObject?
		let status = SecItemCopyMatching([
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
		] as [String: Any] as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func delete(_ account: String) {
		SecItemDelete([
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		] as [String: Any] as CFDictionary)
	}
}
