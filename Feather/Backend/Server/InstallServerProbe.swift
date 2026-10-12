//
//  InstallServerProbe.swift
//  Accretion
//

import Foundation
import Vapor

// MARK: - Install server test
/// Settings → Installation → Test Install Server. Runs the same local server an install uses and
/// checks each step separately, so "iOS didn't ask to install" can be told apart:
///   1. the install mode and its certificate files
///   2. the host name resolving to this device (Fully Local; blocked by DNS rebinding protection)
///   3. the server starting
///   4. the server answering over the same HTTPS name and certificate iOS uses
///   5. the selected certificate's only slot not being Accretion itself
struct InstallServerProbe {
	struct Check: Identifiable {
		enum State { case pass, warn, fail }
		let id = UUID()
		let state: State
		let title: String
		let detail: String
	}

	static func run() async -> [Check] {
		await Task.detached(priority: .userInitiated) { await _run() }.value
	}

	private static func _run() async -> [Check] {
		var checks: [Check] = []
		let method = UserDefaults.standard.integer(forKey: "Feather.serverMethod")
		let fullyLocal = method == 0
		let secure = method != 1
		switch method {
		case 0:
			checks.append(.init(state: .pass, title: String.localized("Mode: Fully Local"), detail: String.localized("Everything stays on this iPhone, over HTTPS with a backloop.dev certificate.")))
		case 2:
			checks.append(.init(state: .pass, title: String.localized("Mode: Offline"), detail: String.localized("Everything stays on this iPhone, over HTTPS with a certificate made on it.")))
			if !LocalCertificateAuthority.isTrusted {
				checks.append(.init(state: .fail, title: String.localized("Offline isn't set up yet"), detail: String.localized("Open Set Up Offline Installs in Settings → Installation → Server & SSL, then test again.")))
			}
		default:
			checks.append(.init(state: .pass, title: String.localized("Mode: Semi Local"), detail: String.localized("The install manifest comes from Accretion's server; the app itself is served from this iPhone.")))
		}

		// the same host an install's link uses
		var host = method == 2 ? LocalCertificateAuthority.host : "127.0.0.1"
		if method == 2 {
			let addresses = _resolve(host)
			if addresses.contains("127.0.0.1") || addresses.contains("::1") {
				checks.append(.init(state: .pass, title: String.localized("Name points to this iPhone"), detail: "\(host) → \(addresses.joined(separator: ", "))"))
			} else {
				checks.append(.init(
					state: .fail,
					title: String.localized("The install name doesn't point to this iPhone"),
					detail: String.localized("%@ resolved to %@ instead of this iPhone.", arguments: host, addresses.isEmpty ? String.localized("nothing") : addresses.joined(separator: ", "))
				))
			}
		}
		if fullyLocal {
			let hasFiles = ServerInstaller.getUrl("server", ext: "crt") != nil && ServerInstaller.getUrl("server", ext: "pem") != nil
			guard hasFiles, let name = ServerInstaller.installHostName() else {
				checks.append(.init(state: .fail, title: String.localized("Certificate files missing"), detail: String.localized("Tap Update SSL Certificates, then test again.")))
				return checks
			}
			host = name
			// which certificate file the server uses and whether it carries the full chain
			if let crt = ServerInstaller.getUrl("server", ext: "crt") {
				let text = (try? String(contentsOf: crt, encoding: .utf8)) ?? ""
				let count = text.components(separatedBy: "BEGIN CERTIFICATE").count - 1
				let origin = crt.path.hasPrefix(URL.documentsDirectory.path) ? String.localized("saved copy") : String.localized("built into this version")
				let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
				checks.append(.init(
					state: count >= 2 ? .pass : .fail,
					title: count >= 2 ? String.localized("Certificate chain complete") : String.localized("Certificate chain incomplete"),
					detail: String.localized("%@ certificate(s), %@, Accretion %@.", arguments: String(count), origin, version)
						+ (count >= 2 ? "" : " " + String.localized("Tap Update SSL Certificates, then test again."))
				))
			}
			let addresses = _resolve(name)
			if addresses.contains("127.0.0.1") {
				checks.append(.init(state: .pass, title: String.localized("Name resolves to this iPhone"), detail: "\(name) → 127.0.0.1"))
			} else {
				checks.append(.init(
					state: .fail,
					title: String.localized("Your network blocks the local name"),
					detail: String.localized("%@ should point to this iPhone (127.0.0.1) but resolved to %@. iCloud Private Relay, Limit IP Address Tracking, a VPN or filtering DNS usually does this. Turn them off, or use Semi Local.", arguments: name, addresses.isEmpty ? String.localized("nothing") : addresses.joined(separator: ", "))
				))
			}
		}

		// start a server exactly like an install does, and ask it for a test page
		let port = Int.random(in: 4000...8000)
		let app = Application(ServerInstaller.env)
		app.threadPool = .init(numberOfThreads: 1)
		do {
			if secure, let tls = try ServerInstaller.tlsConfiguration(method: method) {
				app.http.server.configuration.tlsConfiguration = tls
			}
			app.http.server.configuration.hostname = host
			app.http.server.configuration.address = .hostname(method == 2 ? "::" : "0.0.0.0", port: port)
			app.http.server.configuration.port = port
			app.get("accretion-probe") { _ in "ok" }
			try app.server.start()
			checks.append(.init(state: .pass, title: String.localized("Server starts"), detail: String.localized("Listening on port %@.", arguments: String(port))))
			// what iOS thinks of the certificate the server is using, checked on this iPhone
			if secure, let check = ServerInstaller.lastCheck {
				let which = !fullyLocal
					? String.localized("made on this iPhone")
					: check.saved ? String.localized("saved copy") : String.localized("built into this version")
				let expires = check.expires.formatted(date: .abbreviated, time: .omitted)
				checks.append(.init(
					state: check.trusted ? .pass : .fail,
					title: check.trusted
						? String.localized("iOS trusts the certificate")
						: check.revoked ? String.localized("Certificate withdrawn by its issuer") : String.localized("iOS doesn't trust the certificate"),
					detail: String.localized("%@, %@ certificate(s), expires %@.", arguments: which, String(check.count), expires)
						+ (check.trusted ? "" : "\n\n" + check.reason)
						+ (check.revoked ? "\n\n" + String.localized("Updating it won't help. Use Semi Local or Offline; installs switch automatically.") : "")
				))
			}
		} catch {
			app.shutdown()
			checks.append(.init(state: .fail, title: String.localized("Server didn't start"), detail: error.localizedDescription))
			return checks
		}

		var components = URLComponents()
		components.scheme = secure ? "https" : "http"
		components.host = host
		components.port = port
		components.path = "/accretion-probe"
		let configuration = URLSessionConfiguration.ephemeral
		configuration.timeoutIntervalForRequest = 8
		let session = URLSession(configuration: configuration)
		let watcher = _TLSWatcher()
		do {
			let (data, _) = try await session.data(from: components.url!, delegate: watcher)
			if String(data: data, encoding: .utf8) == "ok" {
				checks.append(.init(
					state: .pass,
					title: String.localized("Server answers"),
					detail: secure
						? String.localized("%@ works, with a valid certificate.", arguments: components.url!.absoluteString)
						: String.localized("%@ works.", arguments: components.url!.absoluteString)
				))
			} else {
				checks.append(.init(state: .fail, title: String.localized("Server answered oddly"), detail: String.localized("Something else answered on that address.")))
			}
		} catch {
			let ns = error as NSError
			let tlsProblem = ns.code == NSURLErrorServerCertificateUntrusted || ns.code == NSURLErrorServerCertificateHasBadDate
				|| ns.code == NSURLErrorSecureConnectionFailed || ns.code == NSURLErrorServerCertificateHasUnknownRoot
			checks.append(.init(
				state: .fail,
				title: tlsProblem ? String.localized("Certificate rejected") : String.localized("Server can't be reached"),
				detail: (tlsProblem
					? String.localized("The install certificate is expired or invalid. Tap Update SSL Certificates, then test again.")
					: String.localized("%@ didn't answer.", arguments: components.url!.absoluteString))
					+ "\n\n" + String.localized("Details: %@ (%@ %@)", arguments: error.localizedDescription, ns.domain, String(ns.code))
					+ _tlsDetails(ns, watcher)
			))
		}
		await app.server.shutdown()
		app.shutdown()

		// the most common non-server cause: Accretion holds the certificate's only app slot
		let slot: Check? = await MainActor.run {
			let cert = Storage.shared.getCertificate(for: UserDefaults.standard.integer(forKey: "feather.selectedCert"))
			guard case .explicit(let id) = CertificateSlots.kind(of: cert), id == Bundle.main.bundleIdentifier else { return nil }
			return Check(
				state: .warn,
				title: String.localized("Accretion uses the certificate's only slot"),
				detail: String.localized("The selected certificate covers one app ID, and it's Accretion's own. Apps signed with it can't install from Accretion (iOS won't replace Accretion while it's open). Install Accretion another way, or use a certificate with more app IDs.")
			)
		}
		if let slot { checks.append(slot) }
		return checks
	}

	/// The lower-level codes behind a failed HTTPS request, and whether the connection got as far as
	/// the certificate check (if it didn't, the handshake itself failed, not the certificate's trust)
	private static func _tlsDetails(_ error: NSError, _ watcher: _TLSWatcher) -> String {
		var parts: [String] = []
		if let stream = error.userInfo["_kCFStreamErrorCodeKey"] { parts.append("stream \(stream)") }
		if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
			parts.append("\(underlying.domain) \(underlying.code)")
		}
		var text = parts.isEmpty ? "" : "\n" + parts.joined(separator: " · ")
		if let result = watcher.result {
			text += "\n" + String.localized("Reached the certificate check: %@", arguments: result)
		} else {
			text += "\n" + String.localized("The connection failed before the certificate check.")
		}
		return text
	}

	/// Every IPv4/IPv6 address the name resolves to on this network
	private static func _resolve(_ name: String) -> [String] {
		var hints = addrinfo()
		hints.ai_family = AF_UNSPEC
		hints.ai_socktype = SOCK_STREAM
		var result: UnsafeMutablePointer<addrinfo>?
		guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return [] }
		defer { freeaddrinfo(result) }
		var addresses: [String] = []
		var pointer: UnsafeMutablePointer<addrinfo>? = first
		while let info = pointer {
			var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
				let address = String(cString: buffer)
				if !addresses.contains(address) { addresses.append(address) }
			}
			pointer = info.pointee.ai_next
		}
		return addresses
	}
}


/// Records how the install server's certificate fared when the test connected to it
private final class _TLSWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
	private(set) var result: String?

	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
		   let trust = challenge.protectionSpace.serverTrust {
			var error: CFError?
			let trusted = SecTrustEvaluateWithError(trust, &error)
			let count = String(SecTrustGetCertificateCount(trust))
			result = trusted
				? String.localized("trusted (%@ certificate(s) sent)", arguments: count)
				: String.localized("not trusted (%@ certificate(s) sent): %@", arguments: count, (error as Error?)?.localizedDescription ?? "?")
		}
		completionHandler(.performDefaultHandling, nil)
	}
}
