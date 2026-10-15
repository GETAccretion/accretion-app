import Foundation

/// Accretion: which sources may offer an update for an app that was installed from somewhere else
/// (handbook issue #29). Only Accretion's own catalogs: the store lists (checked and merged by the
/// store), Accretion Mods and the Accretion app source, and personal copies of them. A source a user
/// added for one app can still update its own apps, but never replace another source's app.
enum UpdateSources {
	static func isAccretionCatalog(_ url: URL) -> Bool {
		guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
		switch host {
		case "getaccretion.app", "www.getaccretion.app", "getaccretion.github.io":
			return true
		case "raw.githubusercontent.com":
			return url.path.hasPrefix("/AccretionMods/mods/") || url.path.hasPrefix("/GETAccretion/accretion-app/")
		case "bbcjpinhvlxocjxlyplt.supabase.co":
			return url.path == "/functions/v1/source"
		default:
			return false
		}
	}
}
