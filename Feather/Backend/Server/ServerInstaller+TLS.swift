import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork
import Security

// MARK: - Class extension: TLS/Setup
extension ServerInstaller {
	// MARK: Setup
	static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()
	
	func setupApp(port: Int) throws -> Application {
		let app = Application(Self.env)
		app.threadPool = .init(numberOfThreads: 1)
		
		if getServerMethod() != 1 {
			do {
				if let tls = try tls() {
					app.http.server.configuration.tlsConfiguration = tls
				}
			} catch {
				app.shutdown()
				throw error
			}
		}
		
		app.http.server.configuration.hostname = sni()
		app.http.server.configuration.tcpNoDelay = true
		app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false
		
		return app
	}
	
	// MARK: Files/IP
	func sni() -> String {
		let localhost = "127.0.0.1"
		
		if getServerMethod() == 1 {
			return !self.getIPFix()
				? (Self.getLocalAddress() ?? localhost)
				: localhost
		} else {
			return readCommonName() ?? localhost
		}
	}
	
	func tls() throws -> TLSConfiguration? {
		try Self.tlsConfiguration()
	}

	/// Accretion: shared with the install server test (Settings → Installation).
	/// Uses the saved certificate (Update SSL Certificates) when iOS trusts it for the install name,
	/// otherwise the copy built into this version. Nothing is deleted: a check that fails here (for
	/// example while offline) mustn't throw away a certificate that still works, and iOS has the final
	/// say. If no copy loads, this throws, instead of starting a plain HTTP server behind an https link.
	static func tlsConfiguration() throws -> TLSConfiguration? {
		var candidates: [(crt: URL, pem: URL, saved: Bool)] = []
		let savedCrt = URL.documentsDirectory.appendingPathComponent("server.crt")
		let savedPem = URL.documentsDirectory.appendingPathComponent("server.pem")
		if FileManager.default.fileExists(atPath: savedCrt.path), FileManager.default.fileExists(atPath: savedPem.path) {
			candidates.append((savedCrt, savedPem, true))
		}
		if let crt = Bundle.main.url(forResource: "server", withExtension: "crt"),
		   let pem = Bundle.main.url(forResource: "server", withExtension: "pem") {
			candidates.append((crt, pem, false))
		}
		guard !candidates.isEmpty else { throw InstallCertificateError.missing }

		let host = installHostName()
		var usable: [(TLSConfiguration, CertificateCheck)] = []
		var loadError: Error?
		for candidate in candidates {
			do {
				let chain = try NIOSSLCertificate.fromPEMFile(candidate.crt.path)
				guard let leaf = chain.first else { throw InstallCertificateError.unreadable }
				let key = try NIOSSLPrivateKey(file: candidate.pem.path, format: .pem)
				let configuration = TLSConfiguration.makeServerConfiguration(
					certificateChain: chain.map { .certificate($0) },
					privateKey: .privateKey(key)
				)
				let expires = Date(timeIntervalSince1970: TimeInterval(leaf.notValidAfter))
				let check = checkCertificate(at: candidate.crt, host: host, saved: candidate.saved, expires: expires)
				if check.trusted {
					lastCheck = check
					return configuration
				}
				usable.append((configuration, check))
			} catch {
				loadError = error
			}
		}
		if let first = usable.first {
			lastCheck = first.1
			return first.0
		}
		throw loadError ?? InstallCertificateError.unreadable
	}

	enum InstallCertificateError: LocalizedError {
		case missing, unreadable
		var errorDescription: String? {
			switch self {
			case .missing: return .localized("The install certificate is missing. Tap Update SSL Certificates in Settings → Installation → Server & SSL.")
			case .unreadable: return .localized("The install certificate can't be read. Tap Update SSL Certificates in Settings → Installation → Server & SSL.")
			}
		}
	}

	/// Whether iOS trusts a certificate file for the install name, and why not
	struct CertificateCheck {
		let trusted: Bool
		let saved: Bool
		let count: Int
		let expires: Date
		let reason: String
	}

	/// The result for the certificate the last server started with (shown by the install server test)
	nonisolated(unsafe) static var lastCheck: CertificateCheck?

	static func checkCertificate(at url: URL, host: String?, saved: Bool, expires: Date) -> CertificateCheck {
		let pem = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
		let certificates = pem
			.components(separatedBy: "-----END CERTIFICATE-----")
			.compactMap { block -> SecCertificate? in
				guard let start = block.range(of: "-----BEGIN CERTIFICATE-----") else { return nil }
				let base64 = block[start.upperBound...].components(separatedBy: .whitespacesAndNewlines).joined()
				guard let der = Data(base64Encoded: base64) else { return nil }
				return SecCertificateCreateWithData(nil, der as CFData)
			}
		func result(_ trusted: Bool, _ reason: String) -> CertificateCheck {
			CertificateCheck(trusted: trusted, saved: saved, count: certificates.count, expires: expires, reason: reason)
		}
		guard !certificates.isEmpty else { return result(false, .localized("No certificate in the file.")) }

		let policy = SecPolicyCreateSSL(true, host as CFString?)
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess, let trust else {
			return result(false, .localized("iOS couldn't read the certificate."))
		}
		var error: CFError?
		if SecTrustEvaluateWithError(trust, &error) {
			return result(true, "")
		}
		// which checks failed (for example AnchorTrusted, SSLHostname, ValidityPeriod, CTRequired)
		var failed: [String] = []
		if let info = SecTrustCopyResult(trust) as? [String: Any],
		   let details = info["TrustResultDetails"] as? [[String: Any]] {
			for item in details { for key in item.keys where !failed.contains(key) { failed.append(key) } }
		}
		let text = (error as Error?)?.localizedDescription ?? .localized("Not trusted.")
		return result(false, failed.isEmpty ? text : "\(text) [\(failed.joined(separator: ", "))]")
	}
	
	func readCommonName() -> String? {
		Self.installHostName()
	}

	/// Accretion: the host name Fully Local installs use (shared with the install server test)
	static func installHostName() -> String? {
		guard let url = Self.getUrl("commonName", ext: "txt") else {
			return nil
		}
		
		guard let name = try? String(contentsOf: url, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
		else {
			return nil
		}
		// Accretion: backloop.dev's certificate is now issued for "*.backloop.dev". Used as-is, the
		// install link pointed at https://*.backloop.dev/… and Fully Local installs never started.
		// Any name under it resolves to this device and is covered by the certificate.
		return name.hasPrefix("*.") ? "local" + name.dropFirst() : name
	}
}

extension ServerInstaller {
	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default
		
		let documentsURL = URL.documentsDirectory.appendingPathComponent("\(name).\(ext)")
		let bundlesURL = Bundle.main.url(forResource: name, withExtension: ext)
		
		if fileManager.fileExists(atPath: documentsURL.path) {
			return documentsURL
		}
		
		if let bundlesURL, fileManager.fileExists(atPath: bundlesURL.path) {
			return bundlesURL
		}
		
		return nil
	}
	
	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				
				if addrFamily == UInt8(AF_INET) {
					
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
						               &hostname, socklen_t(hostname.count),
						               nil, socklen_t(0), NI_NUMERICHOST) == 0 {
							address = String(cString: hostname)
						}
						
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}
		
		return address
	}
}
