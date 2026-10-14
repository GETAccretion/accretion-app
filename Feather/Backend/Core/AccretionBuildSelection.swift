import Foundation

/// Accretion: download authentication and fingerprints follow the server's version rules.
enum AccretionBuildSelection {
	struct Build: Decodable {
		let version: String
		let sha256: String?
	}

	static func select(_ builds: [Build], bundleID: String, version: String?) -> Build? {
		let isAccretion = bundleID == "io.github.getaccretion.Accretion"
		if let version, !version.isEmpty, !isAccretion || AccretionVersion.isBeta(version) {
			return builds.first { $0.version == version }
		}
		return builds.filter { !isAccretion || !AccretionVersion.isBeta($0.version) }
			.max { AccretionVersion.isNewer($1.version, than: $0.version) }
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
