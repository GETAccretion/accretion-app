import Foundation

/// Accretion: the pure rules behind free Apple ID (7-day) signing.

enum AnisetteServers {
	// Mac-backed Anisette v3. State remains isolated by host in AppleIDClient.
	static let own = "https://mac-ani.jkcoxson.com"
	static let maxServers = 6

	static func acceptsCustom(_ text: String) -> Bool { normalized(text) != nil }

	/// The "anisetteServers" strings from the app config JSON; anything unexpected gives []
	static func remoteList(fromAppConfig data: Data) -> [String] {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let list = object["anisetteServers"] as? [Any] else { return [] }
		return list.compactMap { $0 as? String }
	}

	/// Servers to try, in order: custom, own, then remote. https only, no duplicates, at most 6
	static func ordered(custom: String?, remote: [String]) -> [URL] {
		var candidates: [String] = []
		if let custom = custom { candidates.append(custom) }
		candidates.append(own)
		candidates.append(contentsOf: remote)

		var seen = Set<String>()
		var result: [URL] = []
		for text in candidates {
			guard let item = normalized(text), !seen.contains(item.key) else { continue }
			seen.insert(item.key)
			result.append(item.url)
			if result.count >= maxServers { break }
		}
		return result
	}

	/// The cleaned URL and its case-insensitive dedupe key, or nil if it isn't a usable https URL
	private static func normalized(_ text: String) -> (url: URL, key: String)? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let parsed = URLComponents(string: trimmed),
			  parsed.scheme?.lowercased() == "https",
			  let host = parsed.host, !host.isEmpty else { return nil }
		var path = parsed.path
		while path.hasSuffix("/") { path.removeLast() }

		var clean = URLComponents()
		clean.scheme = "https"
		clean.host = host.lowercased()
		clean.port = parsed.port
		clean.path = path
		guard let url = clean.url else { return nil }
		return (url, url.absoluteString.lowercased())
	}
}

enum FreeAccountLimits {
	static let maxActiveApps = 3
	static let maxNewAppIDsPerWeek = 10
	static let profileLifetimeDays = 7

	private static let window = TimeInterval(profileLifetimeDays) * 86_400

	/// App IDs created in the last 7 days (dates in the future don't count)
	static func appIDsUsed(created: [Date], now: Date) -> Int {
		let start = now.addingTimeInterval(-window)
		return created.filter { $0 > start && $0 <= now }.count
	}

	static func canCreate(appIDs needed: Int, created: [Date], now: Date) -> Bool {
		appIDsUsed(created: created, now: now) + needed <= maxNewAppIDsPerWeek
	}

	/// nil if an App ID can be created now, otherwise when the oldest one in the window turns 7 days old
	static func nextFreeSlot(created: [Date], now: Date) -> Date? {
		let start = now.addingTimeInterval(-window)
		let inWindow = created.filter { $0 > start && $0 <= now }
		guard inWindow.count >= maxNewAppIDsPerWeek, let oldest = inWindow.min() else { return nil }
		return oldest.addingTimeInterval(window)
	}
}

enum ProfileExpiry {
	enum Status: Equatable { case ok, soon, expired }

	private static let soonThreshold: TimeInterval = 48 * 3_600

	static func status(expires: Date, now: Date) -> Status {
		if expires <= now { return .expired }
		if expires.timeIntervalSince(now) < soonThreshold { return .soon }
		return .ok
	}

	/// 48 h, 24 h and 2 h before expiry, only those still ahead, earliest first
	static func reminderDates(expires: Date, now: Date) -> [Date] {
		let hoursBefore: [TimeInterval] = [48, 24, 2]
		return hoursBefore
			.map { expires.addingTimeInterval(-$0 * 3_600) }
			.filter { $0 > now }
			.sorted()
	}

	/// Whole days left, rounded down, never negative
	static func daysLeft(expires: Date, now: Date) -> Int {
		let left = expires.timeIntervalSince(now)
		if left <= 0 { return 0 }
		return Int(left / 86_400)
	}
}

enum TeamBundleID {
	/// The bundle ID with ".TEAM" added, unless it already ends with it
	static func signed(original: String, teamID: String) -> String {
		if teamID.isEmpty { return original }
		let suffix = "." + teamID
		return original.hasSuffix(suffix) ? original : original + suffix
	}

	/// Removes one trailing ".TEAM" if present
	static func original(signed: String, teamID: String) -> String {
		if teamID.isEmpty { return signed }
		let suffix = "." + teamID
		guard signed.hasSuffix(suffix) else { return signed }
		return String(signed.dropLast(suffix.count))
	}
}
