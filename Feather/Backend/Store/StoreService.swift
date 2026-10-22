//
//  StoreService.swift
//  Accretion
//

import Foundation
import UIKit

// MARK: - Models (the web store's data feed, built by scripts/site.py in getaccretion.github.io)
struct StoreSource: Decodable, Hashable {
	let name: String
	/// Empty (or missing) when the store keeps source URLs private (PRIVATE_LINKS)
	let url: String?
	let core: Bool?
	let mod: Bool?
}

/// One row of data/store.json, with the web store's short keys.
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
	/// Entitlements and privacy usage keys. Only the names are shown, so the values (whatever
	/// type a source used) are skipped.
	struct Perms: Decodable {
		let entitlements: [String]
		let privacy: [String]

		private struct _Key: CodingKey {
			var stringValue: String
			var intValue: Int? { nil }
			init?(stringValue: String) { self.stringValue = stringValue }
			init?(intValue: Int) { nil }
		}
		private enum CodingKeys: String, CodingKey { case entitlements, privacy }

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			entitlements = (try? container.decode([String].self, forKey: .entitlements)) ?? []
			let privacy = try? container.nestedContainer(keyedBy: _Key.self, forKey: .privacy)
			self.privacy = (privacy?.allKeys.map(\.stringValue) ?? []).sorted()
		}
	}
	let i: String
	let desc: String?
	let tint: String?
	let shots: [String]?
	let versions: [Version]
	let perms: Perms?

	private enum CodingKeys: String, CodingKey { case i, desc, tint, shots, versions, perms }

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		i = try container.decode(String.self, forKey: .i)
		desc = try? container.decode(String.self, forKey: .desc)
		tint = try? container.decode(String.self, forKey: .tint)
		shots = try? container.decode([String].self, forKey: .shots)
		versions = try container.decode([Version].self, forKey: .versions)
		perms = try? container.decode(Perms.self, forKey: .perms)
	}
}

/// data/stats.json: the hero's numbers and build time
struct StoreStats: Decodable {
	let apps: Int?
	let sources: Int?
	let updated_7d: Int?
	let new_30d: Int?
	let updated: String?
}

// MARK: - Service
@MainActor
final class StoreService: ObservableObject {
	static let shared = StoreService()
	static let base = URL(string: "https://getaccretion.app/")!

	static let categoryNames: [String: String] = [
		"games": "Games", "utilities": "Utilities", "photo-video": "Photo & Video",
		"entertainment": "Entertainment", "social": "Social", "lifestyle": "Lifestyle",
		"developer": "Developer", "other": "Other",
	]
	static let categoryOrder = ["games", "entertainment", "utilities", "photo-video", "social", "lifestyle", "developer", "other"]

	@Published private(set) var index: StoreIndex? {
		didSet { _clearCaches() }
	}
	@Published private(set) var stats: StoreStats?
	/// Saved apps (bundle ID → version when saved), like the web store's Save button.
	/// Any change (saving, or opening a saved app's page) clears the caches, so the
	/// "Updates for your saved apps" shelf stays right.
	@Published private(set) var saved: [String: String] = UserDefaults.standard.dictionary(forKey: "accretion.saved") as? [String: String] ?? [:] {
		didSet { _clearCaches() }
	}
	/// Not published: no screen shows it, and each change redrew Discover and every app row
	private(set) var isLoading = false
	@Published private(set) var loadFailed = false
	private var _shards: [Int: [String: StoreAppDetail]] = [:]
	private var _loadedAt: Date?

	private var _cacheFile: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("accretion-store-index.json")
	}

	private init() {}

	/// Shows the last copy before the network answers. Reading and decoding the whole catalogue
	/// takes a moment, so it happens off the main thread (the opening waits for it, see
	/// AccretionWarmUp) instead of inside the first screen.
	func loadCached() async {
		guard index == nil else { return }
		// the opening and Discover both ask at launch; decode the file once
		if _cachedTask == nil {
			let file = _cacheFile
			let view = Self._discoverView()
			let savedNow = self.saved
			_cachedTask = Task.detached(priority: .userInitiated) { () -> _Prepared? in
				guard let data = try? Data(contentsOf: file), let index = Self._decodeIndex(from: data) else { return nil }
				return Self._prepare(index, data: data, saved: savedNow, view: view)
			}
		}
		guard let prepared = await _cachedTask?.value ?? nil else { return }
		if index == nil { _install(prepared) }
	}
	private var _cachedTask: Task<_Prepared?, Never>?

	/// A catalogue with Discover's first shelves and All-apps list already built for it
	private struct _Prepared {
		let index: StoreIndex
		let data: Data
		let onlyFitting: Bool
		let sort: Sort
		let shelves: [Shelf]
		let list: [StoreApp]
	}

	/// Discover's filter and sort, as it saves them (DiscoverView's @AppStorage)
	private static func _discoverView() -> (onlyFitting: Bool, sort: Sort) {
		let defaults = UserDefaults.standard
		return (defaults.object(forKey: "accretion.discover.onlyFitting") as? Bool ?? true,
				Sort(rawValue: defaults.string(forKey: "accretion.discover.sort") ?? "") ?? .updated)
	}

	private nonisolated static func _prepare(_ index: StoreIndex, data: Data, saved: [String: String], view: (onlyFitting: Bool, sort: Sort)) -> _Prepared {
		_Prepared(
			index: index, data: data, onlyFitting: view.onlyFitting, sort: view.sort,
			shelves: _shelves(of: index, saved: saved, onlyFitting: view.onlyFitting),
			list: _sorted(index.apps.filter { !view.onlyFitting || _fits($0) }, by: view.sort)
		)
	}

	/// Sets the catalogue and fills the caches its first drawing asks for, in one main-thread step
	private func _install(_ prepared: _Prepared) {
		index = prepared.index // clears the caches
		_indexBytes = prepared.data
		_shelfCache[prepared.onlyFitting] = (Self._today(), prepared.shelves)
		let key = _SearchKey(query: "", category: nil, onlyFitting: prepared.onlyFitting, sort: prepared.sort)
		_searchCache[key] = prepared.list
		_searchOrder.append(key)
	}
	/// The bytes behind `index`: a download that matches them changes nothing, so nothing is redrawn
	private var _indexBytes: Data?
	private var _statsBytes: Data?

	private nonisolated static func _decodeIndex(from data: Data?) -> StoreIndex? {
		guard let data else { return nil }
		return try? JSONDecoder().decode(StoreIndex.self, from: data)
	}

	// MARK: Loading
	/// The opening and Discover both ask at launch: one download, the second ask waits for the first
	func load(force: Bool = false) async {
		if let running = _loadTask { return await running.value }
		if !force, let loaded = _loadedAt, Date().timeIntervalSince(loaded) < 600 { return }
		let task = Task { await _load() }
		_loadTask = task
		await task.value
		_loadTask = nil
	}
	private var _loadTask: Task<Void, Never>?

	private func _load() async {
		isLoading = true
		defer { isLoading = false }
		await loadCached()
		do {
			let (data, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("data/store.json") /* Accretion 1.0.5+: data/index.json now lists only Accretion, for old copies */)
			// The catalogue changes a few times a day: when the download is what is already shown,
			// keep it. Swapping it in clears every cache and redraws Discover, which the opening felt
			// as a freeze of most of a second (1.0.42's hitch log on an iPhone 17 Pro: 818 ms).
			if index == nil || data != _indexBytes {
				let view = Self._discoverView()
				let savedNow = self.saved
				guard let prepared = await Task.detached(priority: .userInitiated, operation: { () -> _Prepared? in
					Self._decodeIndex(from: data).map { Self._prepare($0, data: data, saved: savedNow, view: view) }
				}).value else {
					throw URLError(.cannotParseResponse)
				}
				_install(prepared)
				let file = _cacheFile
				Task.detached(priority: .utility) { try? data.write(to: file, options: .atomic) }
				_shards = [:]
				_shardTasks = [:]
				_shardGeneration += 1
			}
			_loadedAt = Date()
			if let (statsData, _) = try? await URLSession.shared.data(from: Self.base.appendingPathComponent("data/stats.json")),
			   statsData != _statsBytes {
				stats = try? JSONDecoder().decode(StoreStats.self, from: statsData)
				_statsBytes = statsData
			}
			// published values are only set when they change: every set redraws Discover and each app row
			if loadFailed { loadFailed = false }
		} catch {
			if loadFailed != (index == nil) { loadFailed = index == nil }
		}
	}

	func detail(for app: StoreApp) async -> StoreAppDetail? {
		guard let shard = _shard(of: app) else { return nil }
		if let loaded = _shards[shard] { return loaded[app.i] }
		return await _loadShard(shard)?[app.i]
	}

	/// The app's details when its shard is already here, so its page opens complete
	func cachedDetail(for app: StoreApp) -> StoreAppDetail? {
		_shard(of: app).flatMap { _shards[$0]?[app.i] }
	}

	/// Starts loading the app's details before its page is opened (rows call this as they
	/// come on screen), so the page's zoom lands on the finished page instead of placeholders
	func prefetchDetail(for app: StoreApp) {
		guard let shard = _shard(of: app), _shards[shard] == nil else { return }
		Task { _ = await _loadShard(shard) }
	}

	private func _shard(of app: StoreApp) -> Int? {
		guard let shards = index?.shards, shards > 0 else { return nil }
		return Int(Self.fnv1a(app.i) % UInt32(shards))
	}

	/// One download per shard however many rows and pages ask at once; decoded off the main thread.
	/// A shard that fails is forgotten so the next ask tries again.
	private func _loadShard(_ shard: Int) async -> [String: StoreAppDetail]? {
		if let running = _shardTasks[shard] { return await running.value }
		let url = Self.base.appendingPathComponent(String(format: "data/apps/%03d.json", shard))
		let generation = _shardGeneration
		let task = Task.detached(priority: .userInitiated) { () -> [String: StoreAppDetail]? in
			guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
			return try? JSONDecoder().decode([String: StoreAppDetail].self, from: data)
		}
		_shardTasks[shard] = task
		let decoded = await task.value
		// a fresh catalogue arrived meanwhile: this shard belongs to the old one
		guard generation == _shardGeneration else { return decoded }
		_shardTasks[shard] = nil
		if let decoded { _shards[shard] = decoded }
		return decoded
	}
	private var _shardTasks: [Int: Task<[String: StoreAppDetail]?, Never>] = [:]
	private var _shardGeneration = 0

	/// 32-bit FNV-1a; site.py and the web store use the same hash to pick an app's shard.
	static func fnv1a(_ text: String) -> UInt32 {
		var hash: UInt32 = 0x811C9DC5
		for byte in text.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 0x01000193
		}
		return hash
	}

	// MARK: Saved
	func isSaved(_ app: StoreApp) -> Bool { saved[app.i] != nil }

	func toggleSaved(_ app: StoreApp) {
		if saved[app.i] == nil { saved[app.i] = app.v } else { saved[app.i] = nil }
		UserDefaults.standard.set(saved, forKey: "accretion.saved")
	}

	/// Opening a saved app's page counts as seeing its update, like the web store
	func markSeen(_ app: StoreApp) {
		guard let version = saved[app.i], version != app.v else { return }
		saved[app.i] = app.v
		UserDefaults.standard.set(saved, forKey: "accretion.saved")
	}

	/// Saved apps still in the store, and how many of them have an update (the web's Saved pill)
	func savedSummary() -> (count: Int, updates: Int) {
		guard !saved.isEmpty, let apps = index?.apps else { return (0, 0) }
		var count = 0, updates = 0
		for app in apps where saved[app.i] != nil {
			count += 1
			if saved[app.i] != app.v { updates += 1 }
		}
		return (count, updates)
	}

	/// A saved app whose version moved on since it was saved
	func hasUpdate(_ app: StoreApp) -> Bool {
		guard let version = saved[app.i] else { return false }
		return version != app.v
	}

	// MARK: Questions about apps
	func source(of app: StoreApp) -> StoreSource? {
		guard let sources = index?.sources, sources.indices.contains(app.o) else { return nil }
		return sources[app.o]
	}

	func isMod(_ app: StoreApp) -> Bool { source(of: app)?.mod == true }
	func isCore(_ app: StoreApp) -> Bool { source(of: app)?.core == true }

	/// Same window as the web store: first seen in the last 30 days.
	func isNew(_ app: StoreApp) -> Bool { Self._isNew(app, now: Date()) }

	nonisolated static func _isNew(_ app: StoreApp, now: Date) -> Bool {
		guard let first = app.f, let date = day(first) else { return false }
		return now.timeIntervalSince(date) < 30 * 86400
	}

	/// Whether this device can run it (no minimum, or one at or below this iOS).
	func fits(_ app: StoreApp) -> Bool { Self._fits(app) }

	nonisolated static func _fits(_ app: StoreApp) -> Bool {
		guard let minimum = app.m, !minimum.isEmpty else { return true }
		return !UpdateManager.isVersion(minimum, newerThan: _systemVersion)
	}
	/// Read once: asked for every app each time the shelves or the list are built (ProcessInfo is safe
	/// off the main thread, unlike UIDevice)
	private nonisolated static let _systemVersion: String = {
		let v = ProcessInfo.processInfo.operatingSystemVersion
		return v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
	}()

	/// One formatter for all rows: making one per call cost most of the time building the shelves
	nonisolated(unsafe) private static let _dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = TimeZone(identifier: "UTC")
		return formatter
	}()

	nonisolated static func day(_ text: String) -> Date? {
		_dayFormatter.date(from: String(text.prefix(10)))
	}

	// MARK: Shelves (the same ones as the web store's home page, site/app.js renderShelves)
	struct Shelf: Identifiable {
		let id: String
		let title: String
		let note: String?
		let apps: [StoreApp]
		var ranked = false
		var seeAll: StoreListRoute?
	}

	nonisolated static let shelfSize = 20

	// MARK: Caches
	// Discover and search redraw often; sorting the whole index each time made them lag. Results
	// are kept until the index or the saved apps change. Shelves also depend on the day ("Fresh
	// today", "New this month"), so they're keyed by it. StoreService is @MainActor: no locking.
	private struct _SearchKey: Hashable {
		let query: String
		let category: String?
		let onlyFitting: Bool
		let sort: Sort
	}
	private var _shelfCache: [Bool: (day: String, shelves: [Shelf])] = [:]
	private var _searchCache: [_SearchKey: [StoreApp]] = [:]
	/// Oldest first, so typing a long search keeps only the most recent queries
	private var _searchOrder: [_SearchKey] = []
	private static let _searchCacheSize = 24

	private func _clearCaches() {
		_shelfCache.removeAll()
		_searchCache.removeAll()
		_searchOrder.removeAll()
	}

	private static func _today() -> String {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		let parts = calendar.dateComponents([.year, .month, .day], from: Date())
		return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
	}

	func shelves(onlyFitting: Bool) -> [Shelf] {
		let today = Self._today()
		if let cached = _shelfCache[onlyFitting], cached.day == today { return cached.shelves }
		let shelves = _makeShelves(onlyFitting: onlyFitting)
		_shelfCache[onlyFitting] = (today, shelves)
		return shelves
	}

	private func _makeShelves(onlyFitting: Bool) -> [Shelf] {
		guard let index else { return [] }
		return Self._shelves(of: index, saved: saved, onlyFitting: onlyFitting)
	}

	/// The shelves of one catalogue. It keeps no state, so the first ones are built off the main thread
	/// while the opening plays (loadCached): built on it, Discover's first drawing froze the opening for
	/// over half a second (1.0.43's hitch log on an iPhone 17 Pro: 550-600 ms).
	nonisolated static func _shelves(of index: StoreIndex, saved: [String: String], onlyFitting: Bool) -> [Shelf] {
		let all = index.apps
		func source(_ app: StoreApp) -> StoreSource? { index.sources.indices.contains(app.o) ? index.sources[app.o] : nil }
		let pool = onlyFitting ? all.filter(_fits) : all
		let byUpdated = _sorted(pool, by: .updated)
		let today = Date()
		let fresh = byUpdated.filter { $0.u == nil && (Self.day($0.t).map { today.timeIntervalSince($0) < 2 * 86400 } ?? false) }
		let newThisMonth = _sorted(pool.filter { _isNew($0, now: today) }, by: .new)
		let popular = _sorted(pool.filter { ($0.p ?? 0) > 0 }, by: .popular)
		let mods = byUpdated.filter { source($0)?.mod == true }
		let savedUpdates = pool.filter { app in saved[app.i].map { $0 != app.v } ?? false }
		let core = byUpdated.filter { source($0)?.core == true }
		let games = byUpdated.filter { $0.c == "games" }
		let utilities = byUpdated.filter { $0.c == "utilities" }
		let n = Self.shelfSize
		func route(_ title: String, _ apps: [StoreApp]) -> StoreListRoute { StoreListRoute(title: title, ids: apps.map(\.i)) }

		return [
			Shelf(id: "popular", title: String.localized("Most popular"), note: String.localized("this week"), apps: Array(popular.prefix(n)), ranked: true, seeAll: route(String.localized("Most popular"), popular)),
			Shelf(id: "mods", title: String.localized("Made by Accretion"), note: String.localized("our own mods"), apps: Array(mods.prefix(n)), seeAll: mods.count > n ? route(String.localized("Made by Accretion"), mods) : nil),
			Shelf(id: "saved", title: String.localized("Updates for your saved apps"), note: "\(savedUpdates.count)", apps: Array(savedUpdates.prefix(n)), seeAll: StoreListRoute(title: String.localized("Saved"), saved: true)),
			Shelf(id: "fresh", title: String.localized("Fresh today"), note: String.localized("%@ updated", arguments: fresh.count.formatted()), apps: Array(fresh.prefix(n)), seeAll: route(String.localized("Recently updated"), byUpdated)),
			Shelf(id: "new", title: String.localized("New this month"), note: String.localized("%@ apps", arguments: newThisMonth.count.formatted()), apps: Array(newThisMonth.prefix(n)), seeAll: route(String.localized("Newest apps"), newThisMonth)),
			Shelf(id: "core", title: String.localized("From Accretion Core"), note: String.localized("hand-picked sources"), apps: Array(core.prefix(n))),
			Shelf(id: "games", title: String.localized("Games"), note: String.localized("just updated"), apps: Array(games.prefix(n)), seeAll: StoreListRoute(title: String.localized("Games"), category: "games")),
			Shelf(id: "utilities", title: String.localized("Utilities"), note: String.localized("just updated"), apps: Array(utilities.prefix(n)), seeAll: StoreListRoute(title: String.localized("Utilities"), category: "utilities")),
		].filter { !$0.apps.isEmpty }
	}

	// MARK: Sorting and search (the web store's Sort menu)
	enum Sort: String, CaseIterable, Identifiable {
		case updated, popular, new, name, size
		var id: String { rawValue }
		var title: String {
			switch self {
			case .updated: return String.localized("Recently updated")
			case .popular: return String.localized("Most popular")
			case .new: return String.localized("Newest apps")
			case .name: return String.localized("Name A–Z")
			case .size: return String.localized("Largest")
			}
		}
	}

	func sorted(_ apps: [StoreApp], by sort: Sort) -> [StoreApp] { Self._sorted(apps, by: sort) }

	nonisolated static func _sorted(_ apps: [StoreApp], by sort: Sort) -> [StoreApp] {
		// apps without a date sort last when sorting by update time, like the web store
		let when: (StoreApp) -> String = { $0.u == nil ? $0.t : "" }
		switch sort {
		case .updated: return apps.sorted { when($0) > when($1) }
		case .popular: return apps.sorted { (($0.p ?? 0), when($0)) > (($1.p ?? 0), when($1)) }
		case .new: return apps.sorted { ($0.f ?? "") > ($1.f ?? "") }
		case .name: return apps.sorted { $0.n.localizedCaseInsensitiveCompare($1.n) == .orderedAscending }
		case .size: return apps.sorted { ($0.z ?? 0) > ($1.z ?? 0) }
		}
	}

	func categoryCounts() -> [String: Int] {
		var counts: [String: Int] = [:]
		for app in index?.apps ?? [] { counts[app.c, default: 0] += 1 }
		return counts
	}

	/// Search and category filter for the full list
	func apps(matching query: String, category: String?, onlyFitting: Bool, sort: Sort = .updated) -> [StoreApp] {
		// "Apollo " and "apollo" are the same search
		let key = _SearchKey(
			query: query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
			category: category,
			onlyFitting: onlyFitting,
			sort: sort
		)
		if let cached = _searchCache[key] { return cached }
		let result = _matchApps(key.query, category: category, onlyFitting: onlyFitting, sort: sort)
		guard index != nil else { return result } // don't remember an empty result from before the index loads
		_searchCache[key] = result
		_searchOrder.append(key)
		if _searchOrder.count > Self._searchCacheSize {
			_searchCache[_searchOrder.removeFirst()] = nil
		}
		return result
	}

	private func _matchApps(_ query: String, category: String?, onlyFitting: Bool, sort: Sort) -> [StoreApp] {
		guard let all = index?.apps else { return [] }
		let words = query.lowercased().split(separator: " ").map(String.init)
		let matches = all
			.filter { !onlyFitting || fits($0) }
			.filter { category == nil || $0.c == category }
			.filter { app in
				words.isEmpty || words.allSatisfy { word in
					app.n.lowercased().contains(word) || app.d.lowercased().contains(word) || app.i.lowercased().contains(word)
				}
			}
		guard let first = words.first else { return sorted(matches, by: sort) }
		// like the website: names starting with the search first, then names containing it, then
		// popularity, then the chosen sort
		let ordered = sorted(matches, by: sort)
		let rank: (StoreApp) -> Int = { app in
			let name = app.n.lowercased()
			return name.hasPrefix(first) ? 0 : name.contains(first) ? 1 : 2
		}
		return ordered.enumerated()
			.sorted { lhs, rhs in
				let (l, r) = (rank(lhs.element), rank(rhs.element))
				if l != r { return l < r }
				let (lp, rp) = (lhs.element.p ?? 0, rhs.element.p ?? 0)
				if lp != rp { return lp > rp }
				return lhs.offset < rhs.offset
			}
			.map(\.element)
	}
}
