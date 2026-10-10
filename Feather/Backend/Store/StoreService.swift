//
//  StoreService.swift
//  Accretion
//

import Foundation
import UIKit

// MARK: - Models (the web store's data feed, built by scripts/site.py in getaccretion.github.io)
struct StoreSource: Decodable, Hashable {
	let name: String
	let url: String
	let core: Bool?
	let mod: Bool?
}

/// One row of data/index.json, with the web store's short keys.
struct StoreApp: Decodable, Identifiable, Hashable {
	let i: String         // bundle ID
	let n: String         // name
	let d: String         // developer
	let s: String?        // subtitle
	let c: String         // category
	let v: String         // version
	let t: String         // updated (yyyy-mm-dd)
	let z: Int?           // size in bytes
	let ic: String        // icon URL
	let o: Int            // index into sources
	let m: String?        // minimum iOS
	let f: String?        // first seen (yyyy-mm-dd)
	let p: Double?        // popularity
	let u: Int?           // 1 when the source gives no date

	var id: String { i }
	var iconURL: URL? { URL(string: ic) }
}

struct StoreIndex: Decodable {
	let sources: [StoreSource]
	let shards: Int
	let apps: [StoreApp]
}

/// One app's details from data/apps/NNN.json.
struct StoreAppDetail: Decodable {
	struct Version: Decodable, Hashable {
		let v: String
		let b: String?
		let t: String
		let z: Int?
		let min: String?
		let notes: String?
		let url: String
	}
	let i: String
	let desc: String?
	let tint: String?
	let shots: [String]?
	let versions: [Version]
}

// MARK: - Service
@MainActor
final class StoreService: ObservableObject {
	static let shared = StoreService()
	static let base = URL(string: "https://getaccretion.github.io/")!

	static let categoryNames: [String: String] = [
		"games": "Games", "utilities": "Utilities", "photo-video": "Photo & Video",
		"entertainment": "Entertainment", "social": "Social", "lifestyle": "Lifestyle",
		"developer": "Developer", "other": "Other",
	]
	static let categoryOrder = ["games", "entertainment", "utilities", "photo-video", "social", "lifestyle", "developer", "other"]

	@Published private(set) var index: StoreIndex?
	@Published private(set) var isLoading = false
	@Published private(set) var loadFailed = false
	private var _shards: [Int: [String: StoreAppDetail]] = [:]
	private var _loadedAt: Date?

	private var _cacheFile: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("accretion-store-index.json")
	}

	private init() {
		// show the last copy right away, then refresh
		if let data = try? Data(contentsOf: _cacheFile) {
			index = try? JSONDecoder().decode(StoreIndex.self, from: data)
		}
	}

	// MARK: Loading
	func load(force: Bool = false) async {
		if !force, let loaded = _loadedAt, Date().timeIntervalSince(loaded) < 600 { return }
		isLoading = true
		defer { isLoading = false }
		do {
			let (data, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("data/index.json"))
			index = try JSONDecoder().decode(StoreIndex.self, from: data)
			try? data.write(to: _cacheFile, options: .atomic)
			_shards = [:]
			_loadedAt = Date()
			loadFailed = false
		} catch {
			loadFailed = index == nil
		}
	}

	func detail(for app: StoreApp) async -> StoreAppDetail? {
		guard let shards = index?.shards, shards > 0 else { return nil }
		let shard = Int(Self.fnv1a(app.i) % UInt32(shards))
		if _shards[shard] == nil {
			let url = Self.base.appendingPathComponent(String(format: "data/apps/%03d.json", shard))
			guard
				let response = try? await URLSession.shared.data(from: url),
				let decoded = try? JSONDecoder().decode([String: StoreAppDetail].self, from: response.0)
			else {
				return nil
			}
			_shards[shard] = decoded
		}
		return _shards[shard]?[app.i]
	}

	/// 32-bit FNV-1a; site.py and the web store use the same hash to pick an app's shard.
	static func fnv1a(_ text: String) -> UInt32 {
		var hash: UInt32 = 0x811C9DC5
		for byte in text.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 0x01000193
		}
		return hash
	}

	// MARK: Questions about apps
	func source(of app: StoreApp) -> StoreSource? {
		guard let sources = index?.sources, sources.indices.contains(app.o) else { return nil }
		return sources[app.o]
	}

	func isMod(_ app: StoreApp) -> Bool { source(of: app)?.mod == true }
	func isCore(_ app: StoreApp) -> Bool { source(of: app)?.core == true }

	/// Same window as the web store: first seen in the last 30 days.
	func isNew(_ app: StoreApp) -> Bool {
		guard let first = app.f, let date = Self.day(first) else { return false }
		return Date().timeIntervalSince(date) < 30 * 86400
	}

	/// Whether this device can run it (no minimum, or one at or below this iOS).
	func fits(_ app: StoreApp) -> Bool {
		guard let minimum = app.m, !minimum.isEmpty else { return true }
		return !UpdateManager.isVersion(minimum, newerThan: UIDevice.current.systemVersion)
	}

	static func day(_ text: String) -> Date? {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter.date(from: String(text.prefix(10)))
	}

	// MARK: Shelves (the same ones as the web store's home page)
	struct Shelf: Identifiable {
		let id: String
		let title: String
		let note: String?
		let apps: [StoreApp]
		var ranked = false
	}

	func shelves(onlyFitting: Bool) -> [Shelf] {
		guard let all = index?.apps else { return [] }
		let pool = onlyFitting ? all.filter(fits) : all
		let byUpdated = pool.sorted { $0.t > $1.t }
		let today = Date()
		let fresh = byUpdated.filter { $0.u == nil && (Self.day($0.t).map { today.timeIntervalSince($0) < 2 * 86400 } ?? false) }
		let fresh15 = Array(fresh.prefix(15))
		let newThisMonth = pool.filter(isNew).sorted { ($0.f ?? "") > ($1.f ?? "") }
		let popular = pool.filter { ($0.p ?? 0) > 0 }.sorted { ($0.p ?? 0) > ($1.p ?? 0) }

		return [
			Shelf(id: "popular", title: "Most popular", note: "this week", apps: Array(popular.prefix(15)), ranked: true),
			Shelf(id: "mods", title: "Made by Accretion", note: "our own mods", apps: Array(byUpdated.filter(isMod).prefix(15))),
			Shelf(id: "fresh", title: "Fresh today", note: "\(fresh.count) updated", apps: fresh15),
			Shelf(id: "new", title: "New this month", note: "\(newThisMonth.count) apps", apps: Array(newThisMonth.prefix(15))),
			Shelf(id: "core", title: "From Accretion Core", note: "hand-picked sources", apps: Array(byUpdated.filter(isCore).prefix(15))),
			Shelf(id: "games", title: "Games", note: "just updated", apps: Array(byUpdated.filter { $0.c == "games" }.prefix(15))),
			Shelf(id: "utilities", title: "Utilities", note: "just updated", apps: Array(byUpdated.filter { $0.c == "utilities" }.prefix(15))),
		].filter { !$0.apps.isEmpty }
	}

	/// Search and category filter for the full list, popular apps first among equals.
	func apps(matching query: String, category: String?, onlyFitting: Bool) -> [StoreApp] {
		guard let all = index?.apps else { return [] }
		let words = query.lowercased().split(separator: " ").map(String.init)
		return all
			.filter { !onlyFitting || fits($0) }
			.filter { category == nil || $0.c == category }
			.filter { app in
				words.isEmpty || words.allSatisfy { word in
					app.n.lowercased().contains(word) || app.d.lowercased().contains(word) || app.i.lowercased().contains(word)
				}
			}
			.sorted { (($0.p ?? 0), $0.t) > (($1.p ?? 0), $1.t) }
	}
}
