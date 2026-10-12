//
//  TempCleanup.swift
//  Accretion
//

import Foundation

/// Signing, installing and tweak extraction each leave a working folder in tmp (an install leaves
/// about twice the app's size). At launch, remove the ones older than six hours.
enum TempCleanup {
	private static let prefixes = [
		"FeatherInstall_", "FeatherSigning_", "FeatherTweak_", "AccretionTweak_",
		"AccretionRestore_", "AccretionInject_", "FeatherDownloads",
	]

	static func run() {
		Task.detached(priority: .utility) {
			let fileManager = FileManager.default
			let tmp = fileManager.temporaryDirectory
			let cutoff = Date().addingTimeInterval(-6 * 3600)
			guard let items = try? fileManager.contentsOfDirectory(
				at: tmp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
			) else { return }
			for item in items where prefixes.contains(where: { item.lastPathComponent.hasPrefix($0) }) {
				let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
				if modified < cutoff { try? fileManager.removeItem(at: item) }
			}
		}
	}
}

/// Install certificates saved by older versions held only the server certificate, without the
/// Let's Encrypt intermediates, so iOS rejected the install server. Those saved copies override
/// the full set bundled with the app; remove them (all three files together, so the key and name
/// still match) and the bundled chain is used. "Update SSL Certificates" now saves the full chain.
enum InstallCertificateUpgrade {
	static func run() {
		let documents = URL.documentsDirectory
		let crt = documents.appendingPathComponent("server.crt")
		guard let text = try? String(contentsOf: crt, encoding: .utf8),
			  text.components(separatedBy: "BEGIN CERTIFICATE").count - 1 < 2
		else { return }
		for name in ["server.crt", "server.pem", "commonName.txt"] {
			try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
		}
	}
}

/// Semi Local is the default install mode from 1.0.14 (Fully Local depends on a public certificate
/// that iOS can stop accepting). Moves everyone on Fully Local, including new installs, once.
enum InstallModeDefaults {
	static func run() {
		let defaults = UserDefaults.standard
		guard !defaults.bool(forKey: "accretion.installModeDefaults.v1") else { return }
		if defaults.integer(forKey: "Feather.serverMethod") == 0 {
			defaults.set(1, forKey: "Feather.serverMethod")
		}
		defaults.set(true, forKey: "accretion.installModeDefaults.v1")
	}
}
