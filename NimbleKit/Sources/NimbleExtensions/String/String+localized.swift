//
//  String+localized.swift
//  NimbleKit
//
//  Created by samara on 20.03.2025.
//

import Foundation.NSString
import SwiftUI

extension String {
	// from: https://github.com/NSAntoine/Antoine/blob/main/Antoine/Backend/Extensions/Foundation.swift#L43-L55
	// was given permission to use any code from antoine as I like - thank you Serena!~
	
	static public func localized(_ name: String) -> String {
		// Accretion: its own strings, and the translations Feather's table lacks, are in a second
		// table (Accretion.xcstrings), read when the first has nothing for this language
		let text = NSLocalizedString(name, comment: "")
		return text == name ? NSLocalizedString(name, tableName: "Accretion", comment: "") : text
	}

	static public func localized(_ name: String, arguments: CVarArg...) -> String {
		String(format: String.localized(name), arguments: arguments)
	}
	/// Localizes the current string using the main bundle.
	///
	/// - Returns: The localized string.
	public func localized() -> String {
		String.localized(self)
	}
}

extension LocalizedStringKey {
	static public func localized(_ key: String) -> LocalizedStringKey {
		// Accretion: looked up here, so the second table is read too
		LocalizedStringKey(String.localized(key))
	}
}
