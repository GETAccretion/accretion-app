//
//  ArchiveEntryPath.swift
//  Accretion
//
//  Core: pure logic with no app dependencies, unit-tested by CoreTests (CoreTests/run.sh).
//

import Foundation

/// Whether an archive entry may be written under the folder it is extracted into. An IPA or a
/// tweak archive comes from a source the user added, and an entry named "../Documents/x" would
/// otherwise be written outside the extraction folder, anywhere in Accretion's container (zip-slip).
enum ArchiveEntryPath {
	/// True when `name` stays inside the extraction folder: not absolute, never climbing above
	/// it with "..", and no NUL. Zip entries may use either slash, so both are separators.
	static func isContained(_ name: String) -> Bool {
		let normalized = name.replacingOccurrences(of: "\\", with: "/")
		guard !normalized.isEmpty, !normalized.hasPrefix("/"), !normalized.contains("\0") else { return false }
		var depth = 0
		for component in normalized.split(separator: "/", omittingEmptySubsequences: true) {
			switch component {
			case ".":
				continue
			case "..":
				depth -= 1
				if depth < 0 { return false }
			default:
				depth += 1
			}
		}
		return true
	}

	/// The first entry that would escape the extraction folder, or nil when all stay inside
	static func firstEscaping(_ names: [String]) -> String? {
		names.first { !isContained($0) }
	}
}
