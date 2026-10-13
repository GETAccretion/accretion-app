//
//  AccretionVersion.swift
//  Accretion
//
//  Core: pure logic with no app dependencies, unit-tested by CoreTests (CoreTests/run.sh).
//

import Foundation

/// Version rules shared by app updates, Accretion betas and mod builds. Versions compare number by
/// number, ignoring anything that isn't a number, the same way as the store pipeline and the
/// download server: "1.10" > "1.9", "2.0b" == "2.0", "4.0.0-mod1.10.0" > "4.0.0-mod1.9.0" > "4.0.0".
enum AccretionVersion {
	/// Every number in the version, in order: "4.0.0-mod1.1.0" -> [4, 0, 0, 1, 1, 0]
	static func numbers(_ version: String) -> [Int] {
		version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
	}

	/// Whether `candidate` is newer than `current`; missing numbers count as 0 ("1.0" == "1.0.0")
	static func isNewer(_ candidate: String, than current: String) -> Bool {
		let a = numbers(candidate), b = numbers(current)
		for i in 0..<max(a.count, b.count) {
			let x = i < a.count ? a[i] : 0
			let y = i < b.count ? b[i] : 0
			if x != y { return x > y }
		}
		return false
	}

	/// An Accretion beta: four numbers, between two releases (1.0.25.1 comes after 1.0.25, before 1.0.26)
	static func isBeta(_ version: String) -> Bool {
		version.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
	}
}
