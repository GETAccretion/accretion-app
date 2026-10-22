//
//  AccretionWarmUp.swift
//  Accretion
//

import Foundation
import Nuke

// MARK: - Opening warm-up
/// Work done while the opening shows, so the first screen is complete and smooth when it fades away:
/// the last copy of the catalogue is read off the main thread, the fresh catalogue is fetched (so
/// Discover doesn't swap its content right after the opening), the first shelves are built, and the
/// icons of the first rows are loaded into the image cache (at the size the rows draw them, see
/// StoreAppIcon.processors). Each step moves `progress`, which the opening's bar shows.
/// The opening never waits longer than `cap`; a slow step is cut short and the next one runs.
@MainActor
final class AccretionWarmUp: ObservableObject {
	/// Longest the opening is held in all; a slow network or phone never keeps the app on the logo
	static let cap: TimeInterval = 6
	/// Longest the fresh catalogue is waited for; the saved copy is used when it takes longer
	static let networkCap: TimeInterval = 3
	/// Icons loaded before the opening ends (the first shelves show about this many)
	static let iconCount = 24

	/// 0...1, for the opening's bar
	@Published private(set) var progress: Double = 0
	/// What is being done now, under the bar
	@Published private(set) var step: String = String.localized("Starting")

	/// Returns when the warm-up is done or the cap is reached, whichever is first; the bar ends full either way
	func run() async {
		await withTaskGroup(of: Void.self) { group in
			group.addTask { try? await Task.sleep(nanoseconds: UInt64(Self.cap * 1_000_000_000)) }
			group.addTask { await self._warm() }
			await group.next()
			group.cancelAll()
		}
		_set(1, String.localized("Ready"))
	}

	// shares of the bar: saved catalogue, fresh catalogue, shelves, icons
	private static let shares = (saved: 0.15, fresh: 0.3, shelves: 0.1, icons: 0.45)

	private func _warm() async {
		let store = StoreService.shared
		_set(0.04, String.localized("Reading the catalogue"))
		await store.loadCached()
		guard !Task.isCancelled else { return }

		var done = Self.shares.saved
		_set(done, String.localized("Checking for new apps"))
		await Self._within(Self.networkCap) { await store.load() }
		guard !Task.isCancelled else { return }

		done += Self.shares.fresh
		_set(done, String.localized("Arranging the shelves"))
		await Task.yield()
		let onlyFitting = UserDefaults.standard.object(forKey: "accretion.discover.onlyFitting") as? Bool ?? true
		var seen = Set<String>()
		let urls = store.shelves(onlyFitting: onlyFitting)
			.flatMap(\.apps)
			.filter { seen.insert($0.i).inserted }
			.prefix(Self.iconCount)
			.compactMap(\.iconURL)
		guard !Task.isCancelled else { return }

		done += Self.shares.shelves
		guard !urls.isEmpty else { return }
		let total = urls.count
		_set(done, String.localized("Loading icons 0 of %@", arguments: "\(total)"))
		let pipeline = ImagePipeline.shared
		await withTaskGroup(of: Void.self) { group in
			for url in urls {
				let request = ImageRequest(url: url, processors: StoreAppIcon.processors(for: 48))
				group.addTask { _ = try? await pipeline.image(for: request) }
			}
			var loaded = 0
			for await _ in group {
				loaded += 1
				_set(done + Self.shares.icons * Double(loaded) / Double(total),
					 String.localized("Loading icons %@ of %@", arguments: "\(loaded)", "\(total)"))
			}
		}
	}

	private func _set(_ value: Double, _ text: String) {
		progress = max(progress, min(value, 1))
		step = text
	}

	/// Runs `work` for at most `seconds`; it keeps going in the background when cut short
	private static func _within(_ seconds: TimeInterval, _ work: @escaping @MainActor () async -> Void) async {
		let running = Task { await work() }
		await withTaskGroup(of: Void.self) { group in
			group.addTask { await running.value }
			group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
			await group.next()
			group.cancelAll()
		}
	}
}
