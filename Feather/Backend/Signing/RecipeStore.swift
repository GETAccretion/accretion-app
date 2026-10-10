//
//  RecipeStore.swift
//  Accretion
//

import Foundation
import UIKit

// MARK: - Recipe
/// Everything a user chose when signing one app: name, icon, injected tweaks, properties.
/// Re-applied automatically the next time that app is signed, including after updates, so a
/// tweaked app stays tweaked. Files live in Documents/Recipes/<original bundle ID>/.
struct Recipe: Codable {
	/// Signing options as chosen, with tweak URLs pointing at the recipe's own copies
	var options: Options
	/// The bundle ID the app was last signed as, so re-signing a Signed copy finds the recipe
	var signedIdentifier: String?
	var hasIcon: Bool
	var updated: Date
}

enum RecipeStore {
	private static var _root: URL { URL.documentsDirectory.appendingPathComponent("Recipes") }
	private static func _folder(_ key: String) -> URL { _root.appendingPathComponent(key) }
	private static func _file(_ key: String) -> URL { _folder(key).appendingPathComponent("recipe.json") }
	private static func _icon(_ key: String) -> URL { _folder(key).appendingPathComponent("icon.png") }
	private static func _tweaks(_ key: String) -> URL { _folder(key).appendingPathComponent("Tweaks") }

	// MARK: Lookup
	/// The recipe key for an app: its original bundle ID. A signed copy may carry a different
	/// bundle ID (custom, PPQ or certificate slot), so it's matched through `signedIdentifier`.
	static func key(for app: AppInfoPresentable) -> String? {
		guard let id = app.identifier else { return nil }
		if !app.isSigned || FileManager.default.fileExists(atPath: _file(id).path) { return id }
		return _allKeys().first { _read($0)?.signedIdentifier == id }
	}

	static func hasRecipe(for app: AppInfoPresentable) -> Bool {
		guard let key = key(for: app) else { return false }
		return FileManager.default.fileExists(atPath: _file(key).path)
	}

	/// The app's saved options merged onto the current global ones (post-signing choices and PPQ
	/// stay global), plus its custom icon. Nil when the app has no recipe.
	static func load(for app: AppInfoPresentable, base: Options) -> (options: Options, icon: UIImage?)? {
		guard let key = key(for: app), let recipe = _read(key) else { return nil }
		var options = recipe.options
		options.appVersion = nil
		options.post_installAppAfterSigned = base.post_installAppAfterSigned
		options.post_deleteAppAfterSigned = base.post_deleteAppAfterSigned
		options.ppqProtection = base.ppqProtection
		options.ppqString = base.ppqString
		options.injectionFiles = options.injectionFiles.filter { FileManager.default.fileExists(atPath: $0.path) }
		if let file = options.appEntitlementsFile, !FileManager.default.fileExists(atPath: file.path) {
			options.appEntitlementsFile = nil
		}
		let icon = recipe.hasIcon ? UIImage(contentsOfFile: _icon(key).path) : nil
		return (options, icon)
	}

	// MARK: Save
	/// Saves what was just used to sign `app`. Tweak files are copied in, because the originals
	/// sit in a temporary folder that's cleared at launch.
	static func save(options: Options, icon: UIImage?, for app: AppInfoPresentable) {
		guard let key = key(for: app) else { return }
		let fileManager = FileManager.default
		let tweaks = _tweaks(key)
		try? fileManager.createDirectory(at: tweaks, withIntermediateDirectories: true)

		var saved = options
		saved.appVersion = nil
		saved.injectionFiles = options.injectionFiles.compactMap { url in
			if url.path.hasPrefix(tweaks.path) { return url }
			let copy = tweaks.appendingPathComponent(url.lastPathComponent)
			try? fileManager.removeItem(at: copy)
			return (try? fileManager.copyItem(at: url, to: copy)) != nil ? copy : nil
		}
		// drop tweak copies the recipe no longer uses
		let keep = Set(saved.injectionFiles.map(\.lastPathComponent))
		for file in (try? fileManager.contentsOfDirectory(at: tweaks, includingPropertiesForKeys: nil)) ?? []
		where !keep.contains(file.lastPathComponent) {
			try? fileManager.removeItem(at: file)
		}

		if let data = icon?.pngData() {
			try? data.write(to: _icon(key))
		} else {
			try? fileManager.removeItem(at: _icon(key))
		}

		let recipe = Recipe(
			options: saved,
			signedIdentifier: options.appIdentifier ?? app.identifier,
			hasIcon: icon != nil,
			updated: Date()
		)
		if let data = try? JSONEncoder().encode(recipe) {
			try? data.write(to: _file(key), options: .atomic)
		}
	}

	static func forget(for app: AppInfoPresentable) {
		guard let key = key(for: app) else { return }
		try? FileManager.default.removeItem(at: _folder(key))
	}

	// MARK: Private
	private static func _read(_ key: String) -> Recipe? {
		guard let data = try? Data(contentsOf: _file(key)) else { return nil }
		return try? JSONDecoder().decode(Recipe.self, from: data)
	}

	private static func _allKeys() -> [String] {
		(try? FileManager.default.contentsOfDirectory(atPath: _root.path)) ?? []
	}
}
