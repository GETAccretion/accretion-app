//
//  AccretionSources.swift
//  Accretion
//
//  Core: pure logic with no app dependencies, unit-tested by CoreTests (CoreTests/run.sh).
//

import Foundation

/// Which sources Accretion treats as its own. Feather only offers an app updates from the source
/// it was installed from; Accretion also looks in its own sources for the same bundle ID, so a mod
/// or tweak hosted there still gets its updates. Any other source may only update the apps that
/// came from it: otherwise one added source could offer a "newer version" of every installed app.
enum AccretionSources {
	/// Whether a source may offer updates for apps that were not installed from it: the store
	/// (getaccretion.app), Accretion Mods and the app's own source on GitHub, and a personal
	/// source link made by the store's download server (`accountHost`). https only.
	static func trustsForCrossSourceUpdates(_ url: URL, accountHost: String) -> Bool {
		guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
		let path = url.path
		switch host {
		case "getaccretion.app":
			return true
		case "raw.githubusercontent.com":
			return path.hasPrefix("/AccretionMods/") || path.hasPrefix("/GETAccretion/")
		case accountHost.lowercased():
			return path == "/functions/v1/source"
		default:
			return false
		}
	}
}
