//
//  InstalledApps.swift
//  Accretion
//

import Foundation
import ObjectiveC
import CoreData

// MARK: - Installs that keep an app's own ID
/// Accretion: the rules Mod Studio follows around an install (`dev.py sign`). A copy that keeps the
/// app's own bundle ID installs over whatever this iPhone has under that ID, most often the App Store
/// original, and iOS replaces that app and possibly its data. So Accretion remembers which apps it
/// installed and asks before replacing any other; and after an install the app must be on this iPhone.
enum InstalledApps {
	private static let _key = "Accretion.installedBundleIDs"

	/// Whether iOS lists an app with this bundle ID; nil when it can't tell (the lookup doesn't even
	/// find Accretion itself), so neither check acts on a guess.
	static func isInstalled(_ bundleID: String) -> Bool? {
		guard let own = Bundle.main.bundleIdentifier, _lookup(own) == true else { return nil }
		return _lookup(bundleID)
	}

	/// The apps Accretion put on this iPhone. The first time, every app Accretion has signed counts,
	/// so updating an app installed before this list existed doesn't ask.
	static var installedByAccretion: Set<String> {
		if let saved = UserDefaults.standard.stringArray(forKey: _key) { return Set(saved) }
		let request: NSFetchRequest<Signed> = Signed.fetchRequest()
		let signed = (try? Storage.shared.context.fetch(request)) ?? []
		let seeded = Set(signed.compactMap(\.identifier))
		UserDefaults.standard.set(Array(seeded).sorted(), forKey: _key)
		return seeded
	}

	static func remember(_ bundleID: String) {
		var ids = installedByAccretion
		guard ids.insert(bundleID).inserted else { return }
		UserDefaults.standard.set(Array(ids).sorted(), forKey: _key)
	}

	/// True when installing under this ID would replace an app Accretion didn't install.
	static func replacesOriginal(_ bundleID: String) -> Bool {
		guard bundleID != Bundle.main.bundleIdentifier else { return false }
		return isInstalled(bundleID) == true && !installedByAccretion.contains(bundleID)
	}

	/// After iOS reports the install finished: is the app there? Asks a few times, since the app list
	/// can trail the installer by a moment. nil when the lookup can't tell.
	static func landed(_ bundleID: String) async -> Bool? {
		for attempt in 0..<5 {
			guard let found = isInstalled(bundleID) else { return nil }
			if found { return true }
			if attempt < 4 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
		}
		return false
	}

	struct NotInstalled: LocalizedError {
		let bundleID: String
		var errorDescription: String? {
			.localized("iOS said the install finished, but %@ isn't on this iPhone. Try installing again; if it keeps happening, the certificate or profile may not allow this app.", arguments: bundleID)
		}
	}

	// LSApplicationWorkspace.defaultWorkspace.applicationIsInstalled:, named in base64 like
	// NimbleKit's UIApplication+open_private.swift
	private static func _lookup(_ bundleID: String) -> Bool? {
		guard
			let className = _decode("TFNBcHBsaWNhdGlvbldvcmtzcGFjZQ=="), // LSApplicationWorkspace
			let defaultName = _decode("ZGVmYXVsdFdvcmtzcGFjZQ=="), // defaultWorkspace
			let installedName = _decode("YXBwbGljYXRpb25Jc0luc3RhbGxlZDo="), // applicationIsInstalled:
			let workspaceClass = NSClassFromString(className) as? NSObject.Type,
			let workspace = workspaceClass.perform(NSSelectorFromString(defaultName))?.takeUnretainedValue()
		else { return nil }
		let selector = NSSelectorFromString(installedName)
		guard let method = class_getInstanceMethod(type(of: workspace), selector) else { return nil }
		typealias IsInstalled = @convention(c) (AnyObject, Selector, NSString) -> Bool
		let call = unsafeBitCast(method_getImplementation(method), to: IsInstalled.self)
		return call(workspace, selector, bundleID as NSString)
	}

	private static func _decode(_ base64: String) -> String? {
		Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) }
	}
}
