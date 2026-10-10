//
//  Preflight.swift
//  Accretion
//

import Foundation
import UIKit

// MARK: - Preflight
/// Checks run before signing, so problems show up as plain explanations with a fix instead of
/// a failed install with a raw error code.
@MainActor
enum Preflight {
	struct Problem {
		let title: String
		let message: String
		/// Blocking problems stop signing; the rest are warnings the user can sign past.
		let isBlocking: Bool
	}

	static func problems(
		for app: AppInfoPresentable,
		certificate cert: CertificatePair?,
		options: Options
	) -> [Problem] {
		var problems: [Problem] = []

		// Certificate and profile (only when actually signing, not "Modify" only)
		if let cert, options.signingOption == .default {
			if cert.revoked {
				problems.append(.init(
					title: .localized("Certificate revoked"),
					message: .localized("Apple has revoked this certificate, so apps signed with it won't open. Pick another certificate, or ask your seller for a replacement."),
					isBlocking: true
				))
			}
			if let expiration = cert.expiration, expiration < Date() {
				problems.append(.init(
					title: .localized("Certificate expired"),
					message: .localized("This certificate expired on %@. Import a current one in Settings → Certificates.", arguments: expiration.formatted(date: .abbreviated, time: .omitted)),
					isBlocking: true
				))
			}
			if let profile = Storage.shared.getProvisionFileDecoded(for: cert), profile.ExpirationDate < Date() {
				problems.append(.init(
					title: .localized("Profile expired"),
					message: .localized("The certificate's provisioning profile expired on %@. Download a fresh .mobileprovision from your seller.", arguments: profile.ExpirationDate.formatted(date: .abbreviated, time: .omitted)),
					isBlocking: true
				))
			}
		}

		guard
			let appURL = Storage.shared.getAppDirectory(for: app),
			let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")) as? [String: Any]
		else {
			return problems
		}

		// FairPlay: apps downloaded from the App Store stay encrypted and can't run once re-signed
		if
			let executable = info["CFBundleExecutable"] as? String,
			MachOEncryption.isEncrypted(binaryAt: appURL.appendingPathComponent(executable))
		{
			problems.append(.init(
				title: .localized("App is encrypted"),
				message: .localized("This IPA is still encrypted by the App Store, so it won't open after signing. Use a decrypted copy of the app."),
				isBlocking: true
			))
		}

		// Encrypted extensions only break themselves; "Remove PlugIns" fixes it
		let encryptedExtensions = MachOEncryption.encryptedExtensions(in: appURL)
		if !encryptedExtensions.isEmpty {
			problems.append(.init(
				title: .localized("Encrypted extensions"),
				message: .localized("%@ can't be signed because they're still encrypted. The app may still work; remove them under Advanced → Modify → Frameworks & PlugIns if signing fails.", arguments: encryptedExtensions.joined(separator: ", ")),
				isBlocking: false
			))
		}

		// Minimum iOS, unless the signing options lower it
		let required = options.minimumAppRequirement == .default
			? info["MinimumOSVersion"] as? String
			: options.minimumAppRequirement.rawValue
		let device = UIDevice.current.systemVersion
		if let required, UpdateManager.isVersion(required, newerThan: device) {
			problems.append(.init(
				title: .localized("Needs a newer iOS"),
				message: .localized("This app needs iOS %@ and this device runs %@. It will probably not open. You can lower the requirement under Advanced → Properties, but the app may still crash.", arguments: required, device),
				isBlocking: false
			))
		}

		return problems
	}

	/// Shows the problems. Calls `proceed` right away when there are none, after "Sign Anyway"
	/// when there are only warnings, and never when something is blocking.
	static func confirm(_ problems: [Problem], proceed: @escaping () -> Void) {
		guard !problems.isEmpty else { return proceed() }
		let message = problems.map { "• \($0.title)\n\($0.message)" }.joined(separator: "\n\n")

		if problems.contains(where: \.isBlocking) {
			UIAlertController.showAlertWithOk(title: String.localized("Can't sign this app"), message: message)
			return
		}
		UIAlertController.showAlertWithCancel(
			title: String.localized("Before you sign"),
			message: message,
			actions: [UIAlertAction(title: String.localized("Sign Anyway"), style: .default) { _ in proceed() }]
		)
	}
}

// MARK: - Mach-O encryption
/// Reads LC_ENCRYPTION_INFO(_64) from thin and fat Mach-O files: cryptid 1 means FairPlay-encrypted.
enum MachOEncryption {
	static func isEncrypted(binaryAt url: URL) -> Bool {
		guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= 32 else { return false }

		func u32(_ offset: Int, bigEndian: Bool = false) -> UInt32? {
			guard offset >= 0, offset + 4 <= data.count else { return nil }
			let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
			return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
		}
		func u64(_ offset: Int) -> UInt64? {
			guard offset >= 0, offset + 8 <= data.count else { return nil }
			return UInt64(bigEndian: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) })
		}

		// slice offsets: fat headers are big-endian (0xCAFEBABE / 0xCAFEBABF)
		var slices: [Int] = []
		switch u32(0, bigEndian: true) {
		case 0xCAFEBABE:
			for i in 0..<Int(u32(4, bigEndian: true) ?? 0) {
				if let offset = u32(8 + i * 20 + 8, bigEndian: true) { slices.append(Int(offset)) }
			}
		case 0xCAFEBABF:
			for i in 0..<Int(u32(4, bigEndian: true) ?? 0) {
				if let offset = u64(8 + i * 32 + 8) { slices.append(Int(offset)) }
			}
		default:
			slices = [0]
		}

		for base in slices {
			let headerSize: Int
			switch u32(base) {
			case 0xFEEDFACF: headerSize = 32 // MH_MAGIC_64
			case 0xFEEDFACE: headerSize = 28 // MH_MAGIC
			default: continue
			}
			guard let commandCount = u32(base + 16) else { continue }
			var cursor = base + headerSize
			for _ in 0..<commandCount {
				guard let command = u32(cursor), let size = u32(cursor + 4), size >= 8 else { break }
				// LC_ENCRYPTION_INFO = 0x21, LC_ENCRYPTION_INFO_64 = 0x2C; cryptid sits 16 bytes in
				if command == 0x21 || command == 0x2C, let cryptid = u32(cursor + 16), cryptid != 0 {
					return true
				}
				cursor += Int(size)
			}
		}
		return false
	}

	/// Names of app extensions (PlugIns, Extensions) whose executables are still encrypted.
	static func encryptedExtensions(in appURL: URL) -> [String] {
		let fileManager = FileManager.default
		var names: [String] = []
		for folder in ["PlugIns", "Extensions"] {
			let dir = appURL.appendingPathComponent(folder)
			guard let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
			for item in items where item.pathExtension == "appex" {
				guard
					let info = NSDictionary(contentsOf: item.appendingPathComponent("Info.plist")) as? [String: Any],
					let executable = info["CFBundleExecutable"] as? String,
					isEncrypted(binaryAt: item.appendingPathComponent(executable))
				else {
					continue
				}
				names.append(item.deletingPathExtension().lastPathComponent)
			}
		}
		return names
	}
}

// MARK: - Install errors
/// Turns the raw errors iOS and installd return into an explanation with a fix; the raw text stays
/// underneath for bug reports.
enum InstallErrorText {
	private static let _known: [(match: [String], text: String)] = [
		(["MismatchedApplicationIdentifierEntitlement"],
		 "An app with this bundle ID is already installed with a different certificate. Delete it from your Home Screen first, or sign this one with a different bundle ID."),
		(["ApplicationVerificationFailed", "A valid provisioning profile for this executable was not found", "valid provisioning profile"],
		 "iOS rejected the signature. Usually the certificate was revoked, the profile doesn't include this device, or the profile doesn't allow this bundle ID."),
		(["DeviceOSVersionTooLow", "MinimumOSVersion"],
		 "This app needs a newer iOS than this device has."),
		(["DeviceNotSupportedByThinning", "IncorrectArchitecture", "UIDeviceFamily"],
		 "This app doesn't support this device."),
		(["Encrypted", "cryptid"],
		 "This app is still encrypted by the App Store. Use a decrypted copy."),
		(["timed out", "Could not connect", "NSURLErrorDomain"],
		 "The install couldn't reach the local install server. Keep Accretion open during the install, check Settings → Installation, and try again."),
	]
	
	static func describe(_ error: Error) -> String {
		let raw = String(describing: error)
		guard let hit = _known.first(where: { entry in entry.match.contains { raw.localizedCaseInsensitiveContains($0) } }) else {
			return raw
		}
		return String.localized(hit.text) + "\n\n" + String.localized("Details:") + " " + raw
	}
}
