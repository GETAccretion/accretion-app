//
//  AccretionWarmUp.swift
//  Accretion
//

import Foundation
import Nuke

// MARK: - Opening warm-up
/// Work done while the opening plays, so the first screen is smooth when it fades away: the last
/// copy of the catalogue is read and decoded off the main thread, the first Discover shelves are
/// built, and the icons of the first rows are loaded into the image cache (at the size the rows
/// draw them, see StoreAppIcon.processors). The opening never waits longer than `cap`.
enum AccretionWarmUp {
	/// Longest the opening is held for the warm-up; a slow network or phone never keeps the app on the logo
	static let cap: TimeInterval = 2.5
	/// Icons loaded before the opening ends (the first shelves show about this many)
	static let iconCount = 24

	/// Returns when the warm-up is done or the cap is reached, whichever is first
	@MainActor
	static func run() async {
		await withTaskGroup(of: Void.self) { group in
			group.addTask { try? await Task.sleep(nanoseconds: UInt64(cap * 1_000_000_000)) }
			group.addTask { await _warm() }
			await group.next()
			group.cancelAll()
		}
	}

	@MainActor
	private static func _warm() async {
		let store = StoreService.shared
		await store.loadCached()
		guard !Task.isCancelled else { return }

		let onlyFitting = UserDefaults.standard.object(forKey: "accretion.discover.onlyFitting") as? Bool ?? true
		var seen = Set<String>()
		let apps = store.shelves(onlyFitting: onlyFitting)
			.flatMap(\.apps)
			.filter { seen.insert($0.i).inserted }
			.prefix(iconCount)

		let pipeline = ImagePipeline.shared
		await withTaskGroup(of: Void.self) { group in
			for app in apps {
				guard let url = app.iconURL else { continue }
				let request = ImageRequest(url: url, processors: StoreAppIcon.processors(for: 48))
				group.addTask { _ = try? await pipeline.image(for: request) }
			}
		}
	}
}
