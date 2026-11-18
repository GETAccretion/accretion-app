import Foundation

/// Accretion: Fully Local installs use a public certificate that lasts about 90 days, and the copy
/// built into a version can run out before the next update. This decides when the app fetches the
/// current one by itself (what Update SSL Certificates does by hand).
enum InstallCertificatePlan {
	/// Fetch once the best certificate on the device has less than this left
	static let margin: TimeInterval = 7 * 86400
	/// Wait this long between tries, so a server that still hands out the old one isn't asked at every launch
	static let retryAfter: TimeInterval = 12 * 3600

	/// - Parameters:
	///   - method: the install mode (0 Fully Local, 1 Semi Local, 2 Offline); only Fully Local uses this certificate
	///   - expiries: when each certificate on the device runs out (the saved one, the built-in one)
	///   - lastTry: when the app last fetched one by itself
	static func shouldFetch(method: Int, expiries: [Date], lastTry: Date?, now: Date) -> Bool {
		guard method == 0 else { return false }
		// a last try in the future means the clock was set back: don't let it block the fetch
		if let lastTry, lastTry <= now, now.timeIntervalSince(lastTry) < retryAfter { return false }
		guard let best = expiries.max() else { return true }
		return best.timeIntervalSince(now) < margin
	}
}
