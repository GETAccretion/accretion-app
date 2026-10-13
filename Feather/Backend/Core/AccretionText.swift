//
//  AccretionText.swift
//  Accretion
//
//  Core: pure logic with no app dependencies, unit-tested by CoreTests (CoreTests/run.sh).
//

import Foundation

/// Plain text with tappable https links, like the website's posts. Only https links become links;
/// everything else (http, other schemes, @mentions) stays plain text. (Underlining them is up to
/// the screen: see `accretionPostText` in CommunityViews.)
func accretionLinked(_ text: String) -> AttributedString {
	var result = AttributedString(text)
	guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
	for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
		guard
			let url = match.url, url.scheme == "https",
			let range = Range(match.range, in: text),
			let lower = AttributedString.Index(range.lowerBound, within: result),
			let upper = AttributedString.Index(range.upperBound, within: result)
		else { continue }
		result[lower..<upper].link = url
	}
	return result
}
