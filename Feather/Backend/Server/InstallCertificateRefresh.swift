//
//  InstallCertificateRefresh.swift
//  Accretion
//

import Foundation
import NIOSSL

/// Accretion: in Fully Local mode, fetches the current install certificate by itself when the
/// copies on this device have run out or are about to (InstallCertificatePlan). Runs after launch
/// and is quiet either way: the files change only when a complete new set arrives.
enum InstallCertificateRefresh {
	/// The same pack Update SSL Certificates fetches (ServerView)
	private static let packURL = "https://backloop.dev/pack.json"
	private static let lastTryKey = "accretion.installCertificateRefresh.lastTry"

	static func run() {
		let defaults = UserDefaults.standard
		let files: [URL?] = [
			URL.documentsDirectory.appendingPathComponent("server.crt"),
			Bundle.main.url(forResource: "server", withExtension: "crt"),
		]
		let expiries = files.compactMap { file -> Date? in
			guard let file, let chain = try? NIOSSLCertificate.fromPEMFile(file.path), let leaf = chain.first else { return nil }
			return Date(timeIntervalSince1970: TimeInterval(leaf.notValidAfter))
		}
		guard InstallCertificatePlan.shouldFetch(
			method: defaults.integer(forKey: "Feather.serverMethod"),
			expiries: expiries,
			lastTry: defaults.object(forKey: lastTryKey) as? Date,
			now: Date()
		) else { return }
		defaults.set(Date(), forKey: lastTryKey)
		FR.downloadSSLCertificates(from: packURL, feedback: false) { _ in }
	}
}
