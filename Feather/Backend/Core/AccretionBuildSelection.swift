import Foundation

/// Accretion: download authentication and fingerprints follow the server's version rules.
enum AccretionBuildSelection {
	struct Build: Decodable {
		let version: String
		let sha256: String?
	}

	/// A SHA-256 as the store records it: 64 lowercase hex characters.
	static func isFingerprint(_ value: String?) -> Bool {
		guard let value, value.count == 64 else { return false }
		return value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
	}

	static func select(_ builds: [Build], bundleID: String, version: String?) -> Build? {
		let isAccretion = bundleID == "io.github.getaccretion.Accretion"
		if let version, !version.isEmpty, !isAccretion || AccretionVersion.isBeta(version) {
			return builds.first { $0.version == version }
		}
		return builds.filter { !isAccretion || !AccretionVersion.isBeta($0.version) }
			.max { AccretionVersion.isNewer($1.version, than: $0.version) }
	}

	/// A store download-server link (`https://<host>/functions/v1/download?app=…`). Since the store
	/// stopped publishing source URLs, every app in its data is such a link, not only Accretion's own.
	static func isServerLink(_ url: URL, host: String) -> Bool {
		url.scheme == "https" && url.host == host && url.path == "/functions/v1/download"
	}

	/// A server link that still needs the signed-in user's personal key before it can download.
	static func needsKey(_ url: URL, host: String) -> Bool {
		guard isServerLink(url, host: host) else { return false }
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		return !items.contains { $0.name == "key" && !($0.value ?? "").isEmpty }
	}

	/// The `app` (bundle ID) a server link asks for.
	static func bundleID(in url: URL) -> String? {
		URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "app" }?.value
	}

	static func personalURL(base: URL, bundleID: String, key: String, source: URL, appVersion: String) -> URL? {
		guard var link = URLComponents(url: base.appendingPathComponent("functions/v1/download"), resolvingAgainstBaseURL: false) else { return nil }
		var items = [URLQueryItem(name: "app", value: bundleID), URLQueryItem(name: "key", value: key)]
		if source.scheme == "https", source.host == base.host, source.path == "/functions/v1/download",
		   let requested = URLComponents(url: source, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "version" })?.value,
		   !requested.isEmpty {
			items.append(URLQueryItem(name: "version", value: requested))
		}
		items.append(URLQueryItem(name: "av", value: appVersion))
		link.queryItems = items
		return link.url
	}
}
