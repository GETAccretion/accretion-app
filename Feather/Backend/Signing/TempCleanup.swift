//
//  TempCleanup.swift
//  Accretion
//

import Foundation

/// Signing, installing and tweak extraction each leave a working folder in tmp (an install leaves
/// about twice the app's size). At launch, remove the ones older than six hours.
enum TempCleanup {
	private static let prefixes = [
		"FeatherInstall_", "FeatherSigning_", "FeatherTweak_", "AccretionTweak_",
		"AccretionRestore_", "AccretionInject_", "FeatherDownloads",
	]

	static func run() {
		Task.detached(priority: .utility) {
			let fileManager = FileManager.default
			let tmp = fileManager.temporaryDirectory
			let cutoff = Date().addingTimeInterval(-6 * 3600)
			guard let items = try? fileManager.contentsOfDirectory(
				at: tmp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
			) else { return }
			for item in items where prefixes.contains(where: { item.lastPathComponent.hasPrefix($0) }) {
				let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
				if modified < cutoff { try? fileManager.removeItem(at: item) }
			}
		}
	}
}
