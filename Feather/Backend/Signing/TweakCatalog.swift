//
//  TweakCatalog.swift
//  Accretion
//

import Foundation

// MARK: - Models
/// One entry of the Accretion tweak library (github.com/AccretionMods/mods, tweaks.json).
/// Files are downloaded from the tweak's own project releases; Accretion doesn't re-host them.
struct CatalogTweak: Codable, Identifiable, Hashable {
	let id: String
	let name: String
	let description: String
	/// Bundle IDs of the apps this tweak is made for
	let targets: [String]
	let version: String
	let debURL: URL
	/// Extra .deb or .dylib files the tweak needs injected alongside it
	let requires: [URL]?
	let license: String
	let projectURL: URL?
	let author: String?
}

private struct _CatalogFile: Codable {
	let version: Int
	let tweaks: [CatalogTweak]
}

// MARK: - Catalog
@MainActor
final class TweakCatalog: ObservableObject {
	static let shared = TweakCatalog()
	static let url = URL(string: "https://raw.githubusercontent.com/AccretionMods/mods/main/tweaks.json")!

	@Published private(set) var tweaks: [CatalogTweak] = []
	@Published private(set) var downloading: Set<String> = []
	@Published private(set) var loadFailed = false
	private var _loadedAt: Date?

	private init() {}

	/// Loads the catalog, at most once every 30 minutes.
	func load() async {
		if let loaded = _loadedAt, Date().timeIntervalSince(loaded) < 1800 { return }
		do {
			let (data, _) = try await URLSession.shared.data(from: Self.url)
			tweaks = try JSONDecoder().decode(_CatalogFile.self, from: data).tweaks
				.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
			loadFailed = false
			_loadedAt = Date()
		} catch {
			loadFailed = true
		}
	}

	func suggested(for bundleID: String?) -> [CatalogTweak] {
		guard let bundleID else { return [] }
		return tweaks.filter { $0.targets.contains(bundleID) }
	}

	/// Downloads the tweak and what it requires into a temporary tweak folder (the same place
	/// files picked by hand go), returning the files to add to the signing options.
	func download(_ tweak: CatalogTweak) async throws -> [URL] {
		downloading.insert(tweak.id)
		defer { downloading.remove(tweak.id) }

		var files: [URL] = []
		for url in [tweak.debURL] + (tweak.requires ?? []) {
			let (temp, response) = try await URLSession.shared.download(from: url)
			if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
				throw URLError(.badServerResponse)
			}
			// keep the real file name: the tweak handler goes by the .deb / .dylib extension
			let named = FileManager.default.temporaryDirectory
				.appendingPathComponent("AccretionTweak_\(UUID().uuidString)")
				.appendingPathComponent(url.lastPathComponent)
			try FileManager.default.createDirectory(at: named.deletingLastPathComponent(), withIntermediateDirectories: true)
			try FileManager.default.moveItem(at: temp, to: named)

			let stored: URL = await withCheckedContinuation { continuation in
				FileManager.default.moveAndStore(named, with: "FeatherTweak") { continuation.resume(returning: $0) }
			}
			try? FileManager.default.removeItem(at: named.deletingLastPathComponent())
			files.append(stored)
		}
		return files
	}

	/// Whether the signing options already include this tweak's main file.
	static func isAdded(_ tweak: CatalogTweak, to options: Options) -> Bool {
		options.injectionFiles.contains { $0.lastPathComponent == tweak.debURL.lastPathComponent }
	}
}
