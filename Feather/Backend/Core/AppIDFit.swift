import Foundation

/// Accretion: what a provisioning profile lets you sign. Most cheap certificates are explicit: one
/// App ID. Signing with one while keeping each app's own bundle ID still installs and runs, several
/// apps side by side (tested on iOS 27.2), which is what Feather and ESign do; renaming every app
/// to the profile's ID instead leaves room for one app only.
enum AppIDKind: Equatable {
	/// `TEAM.*` (prefix "") or `TEAM.com.example.*` (prefix "com.example.")
	case wildcard(prefix: String)
	/// `TEAM.com.example.app`: exactly one bundle ID
	case explicit(String)

	/// The kind of a profile's App ID without the team prefix ("*", "com.example.*", "com.example.app")
	init?(appID: String?) {
		guard let id = appID, !id.isEmpty else { return nil }
		if id == "*" { self = .wildcard(prefix: "") }
		else if id.hasSuffix(".*") { self = .wildcard(prefix: String(id.dropLast())) }
		else { self = .explicit(id) }
	}
}

enum AppIDFit {
	/// The bundle ID an app is signed with:
	/// - explicit App ID: the wanted ID (keepOwnID, the default), or the profile's one ID
	/// - prefix wildcard: the wanted ID if it fits, otherwise the prefix plus the wanted ID
	/// - full wildcard or unknown: the wanted ID unchanged
	static func bundleID(_ wanted: String, for kind: AppIDKind?, keepOwnID: Bool) -> String {
		switch kind {
		case .explicit(let id):
			return keepOwnID ? wanted : id
		case .wildcard(let prefix) where !prefix.isEmpty && !wanted.hasPrefix(prefix):
			return prefix + wanted
		default:
			return wanted
		}
	}
}
