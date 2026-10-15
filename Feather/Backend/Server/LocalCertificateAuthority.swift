//
//  LocalCertificateAuthority.swift
//  Accretion
//

import Foundation
import CryptoKit
import Security
import NIOSSL
import Vapor
import UIKit

// MARK: - Offline installs
/// Accretion: the Offline install mode. This iPhone makes its own certificate authority (once) and
/// a server certificate for 127.0.0.1 signed by it. After the user installs the authority as a
/// profile and turns on full trust for it, iOS accepts the local install server with no internet
/// and no third-party certificate. The keys never leave the device and aren't backed up.
enum LocalCertificateAuthority {
	/// The install link's host. iOS refuses an install manifest at "localhost" or 127.0.0.1 without
	/// even connecting, but accepts a name; any name under .localhost points at this iPhone, with no
	/// network needed. The certificate covers it, plus localhost and 127.0.0.1.
	static let host = "accretion.localhost"
	/// Where the profile download server listens (Safari only needs plain HTTP here)
	static let loopback = "127.0.0.1"

	private static var _folder: URL {
		URL.applicationSupportDirectory.appendingPathComponent("LocalInstallCertificate", isDirectory: true)
	}
	private static var _caCert: URL { _folder.appendingPathComponent("ca.crt") }
	private static var _caKey: URL { _folder.appendingPathComponent("ca.key") }
	// v3: the server certificate covers accretion.localhost (a new file name makes older ones get replaced)
	static var serverCert: URL { _folder.appendingPathComponent("server-v3.crt") }
	static var serverKey: URL { _folder.appendingPathComponent("server-v3.key") }

	static var isCreated: Bool {
		FileManager.default.fileExists(atPath: _caCert.path) && FileManager.default.fileExists(atPath: _caKey.path)
	}

	/// The authority's name as it appears in Settings → Certificate Trust Settings
	static var displayName: String? {
		guard let der = caCertificateDER(), let cert = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
		return SecCertificateCopySubjectSummary(cert) as String?
	}

	/// Creates the authority if needed, and a fresh server certificate when it's missing or expires within 30 days
	static func prepare() throws {
		try FileManager.default.createDirectory(at: _folder, withIntermediateDirectories: true)
		var folder = _folder
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		try? folder.setResourceValues(values)

		// Accretion was deleted and reinstalled: bring back the authority the profile trusts
		if !isCreated, let key = _Keychain.read(_Keychain.caKey), let cert = _Keychain.read(_Keychain.caCert) {
			try? FileManager.default.removeItem(at: serverCert)
			try? FileManager.default.removeItem(at: serverKey)
			try _write(key, to: _caKey)
			try _write(cert, to: _caCert)
		}
		if !isCreated { try _makeAuthority() }
		_keepInKeychain()
		if _serverNeedsRenewal() { try _makeServerCertificate() }
	}

	/// Removes everything; the next prepare() makes a new authority, which must be installed and trusted again
	static func reset() {
		try? FileManager.default.removeItem(at: _folder)
		_Keychain.delete(_Keychain.caKey)
		_Keychain.delete(_Keychain.caCert)
	}

	/// The authority also lives in the Keychain, on this device only (never backed up or synced). The
	/// Keychain survives deleting the app, so a reinstall signed with the same certificate finds the
	/// authority the user already trusts and needs no new setup.
	private static func _keepInKeychain() {
		guard let key = try? String(contentsOf: _caKey, encoding: .utf8),
		      let cert = try? String(contentsOf: _caCert, encoding: .utf8)
		else { return }
		if _Keychain.read(_Keychain.caCert) != cert || _Keychain.read(_Keychain.caKey) != key {
			_Keychain.write(_Keychain.caKey, key)
			_Keychain.write(_Keychain.caCert, cert)
		}
	}

	private enum _Keychain {
		static let service = "io.github.getaccretion.localinstall"
		static let caKey = "ca.key"
		static let caCert = "ca.crt"

		private static func _query(_ account: String) -> [String: Any] {
			[
				kSecClass as String: kSecClassGenericPassword,
				kSecAttrService as String: service,
				kSecAttrAccount as String: account,
			]
		}

		static func read(_ account: String) -> String? {
			var query = _query(account)
			query[kSecReturnData as String] = true
			query[kSecMatchLimit as String] = kSecMatchLimitOne
			var result: CFTypeRef?
			guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
			      let data = result as? Data
			else { return nil }
			return String(data: data, encoding: .utf8)
		}

		static func write(_ account: String, _ value: String) {
			delete(account)
			var item = _query(account)
			item[kSecValueData as String] = Data(value.utf8)
			item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
			SecItemAdd(item as CFDictionary, nil)
		}

		static func delete(_ account: String) {
			SecItemDelete(_query(account) as CFDictionary)
		}
	}

	static func tlsConfiguration() throws -> TLSConfiguration {
		try prepare()
		let chain = try NIOSSLCertificate.fromPEMFile(serverCert.path)
		let key = try NIOSSLPrivateKey(file: serverKey.path, format: .pem)
		if let leaf = chain.first {
			ServerInstaller.lastCheck = ServerInstaller.checkCertificate(
				at: serverCert, host: host, saved: true,
				expires: Date(timeIntervalSince1970: TimeInterval(leaf.notValidAfter))
			)
		}
		return TLSConfiguration.makeServerConfiguration(
			certificateChain: chain.map { .certificate($0) },
			privateKey: .privateKey(key)
		)
	}

	/// Whether iOS trusts the server certificate, i.e. the profile is installed and fully trusted
	static var isTrusted: Bool {
		guard isCreated, FileManager.default.fileExists(atPath: serverCert.path) else { return false }
		return ServerInstaller.checkCertificate(at: serverCert, host: host, saved: true, expires: .distantFuture).trusted
	}

	static func caCertificateDER() -> Data? {
		guard let pem = try? String(contentsOf: _caCert, encoding: .utf8) else { return nil }
		return _der(fromPEM: pem)
	}

	/// A configuration profile carrying the authority, for Settings to install
	static func profileData() -> Data? {
		guard let der = caCertificateDER() else { return nil }
		let name = displayName ?? "Accretion Local Install"
		let profile: [String: Any] = [
			"PayloadType": "Configuration",
			"PayloadVersion": 1,
			"PayloadIdentifier": "io.github.getaccretion.localinstall",
			"PayloadUUID": UUID().uuidString,
			"PayloadDisplayName": "Accretion Offline Installs",
			"PayloadDescription": "Lets Accretion install apps from this iPhone without the internet. Made on this iPhone; its key never leaves it.",
			"PayloadOrganization": "Accretion",
			"PayloadContent": [[
				"PayloadType": "com.apple.security.root",
				"PayloadVersion": 1,
				"PayloadIdentifier": "io.github.getaccretion.localinstall.ca",
				"PayloadUUID": UUID().uuidString,
				"PayloadDisplayName": name,
				"PayloadCertificateFileName": "AccretionLocalInstall.cer",
				"PayloadContent": der,
			]],
		]
		return try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
	}

	// MARK: Making certificates

	private static func _makeAuthority() throws {
		let key = P256.Signing.PrivateKey()
		let tag = String(UUID().uuidString.prefix(4))
		let name = _name("Accretion Local Install \(tag)")
		let ski = _keyIdentifier(key.publicKey)
		let now = Date()
		let der = try _certificate(
			issuer: name,
			subject: name,
			notBefore: now.addingTimeInterval(-3600),
			notAfter: now.addingTimeInterval(10 * 365 * 86400),
			spki: key.publicKey.derRepresentation,
			extensions: [
				_extension("2.5.29.19", critical: true, DER.sequence([DER.bool(true)])),
				_extension("2.5.29.15", critical: true, DER.bits(Data([0x06]), unused: 1)), // keyCertSign, cRLSign
				_extension("2.5.29.14", critical: false, DER.octet(ski)),
				// nameConstraints: it can only vouch for this iPhone's own names (any *.localhost name,
				// 127.0.0.1 and ::1), so a copied key can't impersonate a website (issue #30)
				_extension("2.5.29.30", critical: true, DER.sequence([DER.tlv(0xA0, [
					DER.sequence([DER.tlv(0x82, Data("localhost".utf8))]),
					DER.sequence([DER.tlv(0x87, Data([127, 0, 0, 1, 255, 255, 255, 255]))]),
					DER.sequence([DER.tlv(0x87, Data(repeating: 0, count: 15) + Data([1]) + Data(repeating: 255, count: 16))]),
				].reduce(Data(), +))])),
			],
			signer: key
		)
		// a new authority means a new server certificate
		try? FileManager.default.removeItem(at: serverCert)
		try _write(key.pemRepresentation, to: _caKey)
		try _write(_pem(der, label: "CERTIFICATE"), to: _caCert)
	}

	private static func _makeServerCertificate() throws {
		guard let caPEM = try? String(contentsOf: _caKey, encoding: .utf8),
		      let caDER = caCertificateDER()
		else { throw CocoaError(.fileReadCorruptFile) }
		let caKey = try P256.Signing.PrivateKey(pemRepresentation: caPEM)
		let issuer = try _subject(ofCertificate: caDER)
		// An RSA server key, like the public certificates iOS's installer has always accepted
		// (the authority above stays P-256, so a trusted profile keeps working)
		let key = try _RSAKey()
		let now = Date()
		let san = DER.sequence([
			DER.tlv(0x82, Data(host.utf8)),               // dNSName
			DER.tlv(0x82, Data("localhost".utf8)),        // dNSName
			DER.tlv(0x87, Data([127, 0, 0, 1])),          // iPAddress
		])
		let der = try _certificate(
			issuer: issuer,
			subject: _name("Accretion Local Install Server"),
			notBefore: now.addingTimeInterval(-3600),
			notAfter: now.addingTimeInterval(390 * 86400),
			spki: key.spki,
			extensions: [
				_extension("2.5.29.19", critical: true, DER.sequence([])),
				_extension("2.5.29.15", critical: true, DER.bits(Data([0xA0]), unused: 5)), // digitalSignature, keyEncipherment
				_extension("2.5.29.37", critical: false, DER.sequence([DER.oid("1.3.6.1.5.5.7.3.1")])), // serverAuth
				_extension("2.5.29.17", critical: false, san),
				_extension("2.5.29.14", critical: false, DER.octet(Data(Insecure.SHA1.hash(data: key.publicPKCS1)))),
				_extension("2.5.29.35", critical: false, DER.sequence([DER.tlv(0x80, _keyIdentifier(caKey.publicKey))])),
			],
			signer: caKey
		)
		try _write(_pem(key.privatePKCS1, label: "RSA PRIVATE KEY"), to: serverKey)
		try _write(_pem(der, label: "CERTIFICATE") + _pem(caDER, label: "CERTIFICATE"), to: serverCert)
	}

	private static func _serverNeedsRenewal() -> Bool {
		guard FileManager.default.fileExists(atPath: serverKey.path),
		      let leaf = try? NIOSSLCertificate.fromPEMFile(serverCert.path).first
		else { return true }
		// server certificates made before 1.0.19 used P-256; replace them with RSA
		if let key = try? String(contentsOf: serverKey, encoding: .utf8), !key.contains("RSA PRIVATE KEY") { return true }
		let expires = Date(timeIntervalSince1970: TimeInterval(leaf.notValidAfter))
		return expires.timeIntervalSinceNow < 30 * 86400
	}

	/// A 2048-bit RSA key from the Security framework, in the forms a certificate and NIOSSL need
	private struct _RSAKey {
		let privatePKCS1: Data
		let publicPKCS1: Data
		/// SubjectPublicKeyInfo: rsaEncryption with NULL parameters, then the PKCS#1 public key
		var spki: Data {
			DER.sequence([
				DER.sequence([DER.oid("1.2.840.113549.1.1.1"), Data([0x05, 0x00])]),
				DER.bits(publicPKCS1),
			])
		}

		init() throws {
			let attributes: [String: Any] = [
				kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
				kSecAttrKeySizeInBits as String: 2048,
			]
			var error: Unmanaged<CFError>?
			guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
			      let publicKey = SecKeyCopyPublicKey(privateKey),
			      let privateData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data?,
			      let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
			else { throw error?.takeRetainedValue() ?? CocoaError(.featureUnsupported) }
			privatePKCS1 = privateData
			publicPKCS1 = publicData
		}
	}

	private static func _certificate(
		issuer: Data,
		subject: Data,
		notBefore: Date,
		notAfter: Date,
		spki: Data,
		extensions: [Data],
		signer: P256.Signing.PrivateKey
	) throws -> Data {
		var serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
		serial[0] = (serial[0] & 0x7F) | 0x01 // positive and non-zero
		let algorithm = DER.sequence([DER.oid("1.2.840.10045.4.3.2")]) // ecdsa-with-SHA256
		let tbs = DER.sequence([
			DER.explicit(0, DER.integer(Data([2]))), // v3
			DER.integer(serial),
			algorithm,
			issuer,
			DER.sequence([DER.utcTime(notBefore), DER.utcTime(notAfter)]),
			subject,
			spki,
			DER.explicit(3, DER.sequence(extensions)),
		])
		let signature = try signer.signature(for: tbs).derRepresentation
		return DER.sequence([tbs, algorithm, DER.bits(signature)])
	}

	private static func _name(_ commonName: String) -> Data {
		DER.sequence([
			DER.set([DER.sequence([DER.oid("2.5.4.10"), DER.utf8("Accretion")])]),
			DER.set([DER.sequence([DER.oid("2.5.4.3"), DER.utf8(commonName)])]),
		])
	}

	/// The subject Name of a certificate, as raw DER, so the server certificate's issuer matches exactly
	private static func _subject(ofCertificate der: Data) throws -> Data {
		var reader = DER.Reader(der)
		var certificate = try reader.enter()       // Certificate
		var tbs = try certificate.enter()          // TBSCertificate
		_ = try tbs.next()                         // [0] version
		_ = try tbs.next()                         // serial
		_ = try tbs.next()                         // signature algorithm
		_ = try tbs.next()                         // issuer
		_ = try tbs.next()                         // validity
		return try tbs.next()                      // subject
	}

	private static func _extension(_ oid: String, critical: Bool, _ value: Data) -> Data {
		var parts = [DER.oid(oid)]
		if critical { parts.append(DER.bool(true)) }
		parts.append(DER.octet(value))
		return DER.sequence(parts)
	}

	private static func _keyIdentifier(_ key: P256.Signing.PublicKey) -> Data {
		Data(Insecure.SHA1.hash(data: key.x963Representation))
	}

	private static func _pem(_ der: Data, label: String) -> String {
		let body = der.base64EncodedString(options: .lineLength64Characters).replacingOccurrences(of: "\r\n", with: "\n")
		return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
	}

	private static func _der(fromPEM pem: String) -> Data? {
		guard let start = pem.range(of: "-----BEGIN CERTIFICATE-----"),
		      let end = pem.range(of: "-----END CERTIFICATE-----", range: start.upperBound..<pem.endIndex)
		else { return nil }
		let base64 = pem[start.upperBound..<end.lowerBound].components(separatedBy: .whitespacesAndNewlines).joined()
		return Data(base64Encoded: base64)
	}

	private static func _write(_ text: String, to url: URL) throws {
		try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
	}
}

// MARK: - DER
/// Just enough DER to write two certificates
private enum DER {
	static func tlv(_ tag: UInt8, _ content: Data) -> Data {
		var out = Data([tag])
		out.append(length(content.count))
		out.append(content)
		return out
	}

	static func length(_ count: Int) -> Data {
		if count < 0x80 { return Data([UInt8(count)]) }
		var bytes: [UInt8] = []
		var value = count
		while value > 0 {
			bytes.insert(UInt8(value & 0xFF), at: 0)
			value >>= 8
		}
		return Data([0x80 | UInt8(bytes.count)] + bytes)
	}

	static func sequence(_ parts: [Data]) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
	static func set(_ parts: [Data]) -> Data { tlv(0x31, parts.reduce(Data(), +)) }
	static func explicit(_ number: UInt8, _ content: Data) -> Data { tlv(0xA0 | number, content) }
	static func octet(_ content: Data) -> Data { tlv(0x04, content) }
	static func utf8(_ text: String) -> Data { tlv(0x0C, Data(text.utf8)) }
	static func bool(_ value: Bool) -> Data { tlv(0x01, Data([value ? 0xFF : 0x00])) }

	static func bits(_ content: Data, unused: UInt8 = 0) -> Data {
		var body = Data([unused])
		body.append(content)
		return tlv(0x03, body)
	}

	/// A non-negative INTEGER from big-endian bytes
	static func integer(_ bytes: Data) -> Data {
		var body = Data(bytes.drop(while: { $0 == 0 }))
		if body.isEmpty { body = Data([0]) }
		if body[body.startIndex] & 0x80 != 0 { body.insert(0, at: body.startIndex) }
		return tlv(0x02, body)
	}

	static func oid(_ dotted: String) -> Data {
		let numbers = dotted.split(separator: ".").compactMap { UInt64($0) }
		var body = Data([UInt8(numbers[0] * 40 + numbers[1])])
		for number in numbers.dropFirst(2) {
			var chunk: [UInt8] = [UInt8(number & 0x7F)]
			var rest = number >> 7
			while rest > 0 {
				chunk.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
				rest >>= 7
			}
			body.append(contentsOf: chunk)
		}
		return tlv(0x06, body)
	}

	static func utcTime(_ date: Date) -> Data {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyMMddHHmmss'Z'"
		return tlv(0x17, Data(formatter.string(from: date).utf8))
	}

	/// Walks DER elements: next() returns a whole element, enter() steps inside a constructed one
	struct Reader {
		private let bytes: [UInt8]
		private var index = 0

		init(_ data: Data) { bytes = [UInt8](data) }

		private mutating func _header() throws -> (start: Int, contentStart: Int, end: Int) {
			let start = index
			guard index + 1 < bytes.count else { throw CocoaError(.fileReadCorruptFile) }
			index += 1 // tag
			var length = Int(bytes[index])
			index += 1
			if length & 0x80 != 0 {
				let count = length & 0x7F
				guard count > 0, count <= 4, index + count <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
				length = 0
				for _ in 0..<count {
					length = (length << 8) | Int(bytes[index])
					index += 1
				}
			}
			guard index + length <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
			return (start, index, index + length)
		}

		mutating func next() throws -> Data {
			let header = try _header()
			index = header.end
			return Data(bytes[header.start..<header.end])
		}

		mutating func enter() throws -> Reader {
			let header = try _header()
			index = header.end
			return Reader(Data(bytes[header.contentStart..<header.end]))
		}
	}
}

// MARK: - Profile download
/// Serves the authority's profile on 127.0.0.1 for a minute and opens it in Safari, which hands it
/// to Settings. The app stays alive in the background for that time.
final class LocalCertificateProfileServer {
	static let shared = LocalCertificateProfileServer()
	private var _app: Application?
	private var _task: UIBackgroundTaskIdentifier = .invalid

	@MainActor
	func open() throws {
		stop()
		try LocalCertificateAuthority.prepare()
		guard let profile = LocalCertificateAuthority.profileData() else { throw CocoaError(.fileReadCorruptFile) }
		let port = Int.random(in: 4000...8000)
		let app = Application(ServerInstaller.env)
		app.threadPool = .init(numberOfThreads: 1)
		app.http.server.configuration.hostname = LocalCertificateAuthority.loopback
		app.http.server.configuration.address = .hostname(LocalCertificateAuthority.loopback, port: port)
		app.http.server.configuration.port = port
		app.get("accretion-offline.mobileconfig") { _ in
			Response(
				status: .ok,
				headers: ["Content-Type": "application/x-apple-aspen-config"],
				body: .init(data: profile)
			)
		}
		do {
			try app.server.start()
		} catch {
			app.shutdown()
			throw error
		}
		_app = app
		_task = UIApplication.shared.beginBackgroundTask { [weak self] in self?.stop() }
		DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.stop() }
		if let url = URL(string: "http://\(LocalCertificateAuthority.loopback):\(port)/accretion-offline.mobileconfig") {
			UIApplication.shared.open(url)
		}
	}

	func stop() {
		if let app = _app {
			_app = nil
			app.server.shutdown()
			app.shutdown()
		}
		if _task != .invalid {
			UIApplication.shared.endBackgroundTask(_task)
			_task = .invalid
		}
	}
}
