import XCTest
@testable import AccretionCore

final class AppleIDPlanTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)
	private let day: TimeInterval = 86_400
	private let hour: TimeInterval = 3_600

	// MARK: AnisetteServers

	private func config(_ json: String) -> Data { Data(json.utf8) }

	func testRemoteListReadsStrings() {
		let data = config(#"{"anisetteServers":["https://a.example","https://b.example"]}"#)
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: data), ["https://a.example", "https://b.example"])
	}

	func testRemoteListIgnoresNonStrings() {
		let data = config(#"{"anisetteServers":["https://a.example",1,null,{"x":1},"https://b.example"]}"#)
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: data), ["https://a.example", "https://b.example"])
	}

	func testRemoteListToleratesBadInput() {
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: config("{}")), [])
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: config(#"{"anisetteServers":"https://a.example"}"#)), [])
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: config(#"{"anisetteServers":{"a":1}}"#)), [])
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: config("[1,2]")), [])
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: config("not json")), [])
		XCTAssertEqual(AnisetteServers.remoteList(fromAppConfig: Data()), [])
	}

	func testOrderIsCustomThenOwnThenRemote() {
		let urls = AnisetteServers.ordered(custom: "https://mine.example", remote: ["https://r1.example", "https://r2.example"])
		XCTAssertEqual(urls.map(\.absoluteString), [
			"https://mine.example", AnisetteServers.own, "https://r1.example", "https://r2.example",
		])
	}

	func testOrderWithoutCustom() {
		XCTAssertEqual(AnisetteServers.ordered(custom: nil, remote: []).map(\.absoluteString), [AnisetteServers.own])
		XCTAssertEqual(AnisetteServers.ordered(custom: "", remote: []).map(\.absoluteString), [AnisetteServers.own])
		XCTAssertEqual(AnisetteServers.ordered(custom: "   ", remote: []).map(\.absoluteString), [AnisetteServers.own])
	}

	func testInvalidCustomIsSkipped() {
		for bad in ["not a url", "ani.example.com", "http://mine.example", "https://", "ftp://mine.example"] {
			XCTAssertEqual(AnisetteServers.ordered(custom: bad, remote: []).map(\.absoluteString), [AnisetteServers.own], bad)
		}
	}

	func testHttpIsRejectedEverywhere() {
		let urls = AnisetteServers.ordered(custom: nil, remote: ["http://plain.example", "https://ok.example"])
		XCTAssertEqual(urls.map(\.absoluteString), [AnisetteServers.own, "https://ok.example"])
	}

	func testWhitespaceIsTrimmed() {
		let urls = AnisetteServers.ordered(custom: "  https://mine.example \n", remote: [])
		XCTAssertEqual(urls.first?.absoluteString, "https://mine.example")
	}

	func testTrailingSlashIsDropped() {
		let urls = AnisetteServers.ordered(custom: "https://mine.example/", remote: ["https://r.example/v3/"])
		XCTAssertEqual(urls.map(\.absoluteString), ["https://mine.example", AnisetteServers.own, "https://r.example/v3"])
	}

	func testDuplicatesAreRemovedIgnoringCaseAndSlash() {
		let remote = ["HTTPS://ANI.GetAccretion.app/", "https://ani.getaccretion.app", "https://x.example", "https://X.example/"]
		let urls = AnisetteServers.ordered(custom: "https://Ani.getaccretion.app//", remote: remote)
		XCTAssertEqual(urls.map(\.absoluteString), [AnisetteServers.own, "https://x.example"])
	}

	func testPortAndPathMakeServersDistinct() {
		let urls = AnisetteServers.ordered(custom: nil, remote: ["https://x.example:8443", "https://x.example", "https://x.example/a", "https://x.example:8443/"])
		XCTAssertEqual(urls.map(\.absoluteString), [
			AnisetteServers.own, "https://x.example:8443", "https://x.example", "https://x.example/a",
		])
	}

	func testAtMostSixServers() {
		let remote = (1...10).map { "https://r\($0).example" }
		let urls = AnisetteServers.ordered(custom: "https://mine.example", remote: remote)
		XCTAssertEqual(urls.count, 6)
		XCTAssertEqual(urls.first?.absoluteString, "https://mine.example")
		XCTAssertEqual(urls.last?.absoluteString, "https://r4.example")
	}

	// MARK: FreeAccountLimits

	func testLimitConstants() {
		XCTAssertEqual(FreeAccountLimits.maxActiveApps, 3)
		XCTAssertEqual(FreeAccountLimits.maxNewAppIDsPerWeek, 10)
		XCTAssertEqual(FreeAccountLimits.profileLifetimeDays, 7)
	}

	func testAppIDsUsedCountsTheLastSevenDays() {
		let created = [now.addingTimeInterval(-1 * day), now.addingTimeInterval(-6 * day), now.addingTimeInterval(-8 * day)]
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: created, now: now), 2)
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: [], now: now), 0)
	}

	func testAppIDsUsedWindowBoundary() {
		let exactly7Days = now.addingTimeInterval(-7 * day)
		let justInside = now.addingTimeInterval(-7 * day + 1)
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: [exactly7Days], now: now), 0, "7 days old is out")
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: [justInside], now: now), 1)
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: [now], now: now), 1, "created right now counts")
	}

	func testAppIDsUsedIgnoresFutureDates() {
		let created = [now.addingTimeInterval(1), now.addingTimeInterval(day), now.addingTimeInterval(-day)]
		XCTAssertEqual(FreeAccountLimits.appIDsUsed(created: created, now: now), 1)
	}

	func testCanCreate() {
		let nine = (1...9).map { now.addingTimeInterval(-Double($0) * hour) }
		XCTAssertTrue(FreeAccountLimits.canCreate(appIDs: 1, created: nine, now: now))
		XCTAssertFalse(FreeAccountLimits.canCreate(appIDs: 2, created: nine, now: now))
		XCTAssertTrue(FreeAccountLimits.canCreate(appIDs: 10, created: [], now: now))
		XCTAssertFalse(FreeAccountLimits.canCreate(appIDs: 11, created: [], now: now))
		XCTAssertTrue(FreeAccountLimits.canCreate(appIDs: 0, created: [], now: now))
	}

	func testCanCreateIgnoresOldAndFutureDates() {
		let old = (1...10).map { now.addingTimeInterval(-8 * day - Double($0)) }
		XCTAssertTrue(FreeAccountLimits.canCreate(appIDs: 10, created: old, now: now))
		let future = (1...10).map { now.addingTimeInterval(Double($0) * hour) }
		XCTAssertTrue(FreeAccountLimits.canCreate(appIDs: 10, created: future, now: now))
	}

	func testNextFreeSlotIsNilWhileASlotIsFree() {
		XCTAssertNil(FreeAccountLimits.nextFreeSlot(created: [], now: now))
		let nine = (1...9).map { now.addingTimeInterval(-Double($0) * hour) }
		XCTAssertNil(FreeAccountLimits.nextFreeSlot(created: nine, now: now))
	}

	func testNextFreeSlotIsWhenTheOldestTurnsSevenDaysOld() {
		let oldest = now.addingTimeInterval(-5 * day)
		var created = (1...9).map { now.addingTimeInterval(-Double($0) * hour) }
		created.append(oldest)
		XCTAssertEqual(FreeAccountLimits.nextFreeSlot(created: created, now: now), oldest.addingTimeInterval(7 * day))
	}

	func testNextFreeSlotIgnoresOutsideTheWindow() {
		let tenOld = (1...10).map { now.addingTimeInterval(-8 * day - Double($0)) }
		XCTAssertNil(FreeAccountLimits.nextFreeSlot(created: tenOld, now: now))
		let inside = (1...9).map { now.addingTimeInterval(-Double($0) * hour) }
		let created = inside + tenOld + [now.addingTimeInterval(day)]
		XCTAssertNil(FreeAccountLimits.nextFreeSlot(created: created, now: now), "old and future dates don't fill the week")
	}

	// MARK: ProfileExpiry

	func testStatusBoundaries() {
		XCTAssertEqual(ProfileExpiry.status(expires: now, now: now), .expired, "exactly at expiry")
		XCTAssertEqual(ProfileExpiry.status(expires: now.addingTimeInterval(-1), now: now), .expired)
		XCTAssertEqual(ProfileExpiry.status(expires: now.addingTimeInterval(1), now: now), .soon)
		XCTAssertEqual(ProfileExpiry.status(expires: now.addingTimeInterval(48 * hour - 1), now: now), .soon)
		XCTAssertEqual(ProfileExpiry.status(expires: now.addingTimeInterval(48 * hour), now: now), .ok, "exactly 48 h left")
		XCTAssertEqual(ProfileExpiry.status(expires: now.addingTimeInterval(7 * day), now: now), .ok)
	}

	func testReminderDatesAllAhead() {
		let expires = now.addingTimeInterval(7 * day)
		XCTAssertEqual(ProfileExpiry.reminderDates(expires: expires, now: now), [
			expires.addingTimeInterval(-48 * hour),
			expires.addingTimeInterval(-24 * hour),
			expires.addingTimeInterval(-2 * hour),
		])
	}

	func testReminderDatesSkipPastOnes() {
		let expires = now.addingTimeInterval(30 * hour)
		XCTAssertEqual(ProfileExpiry.reminderDates(expires: expires, now: now), [
			expires.addingTimeInterval(-24 * hour),
			expires.addingTimeInterval(-2 * hour),
		])
		let soon = now.addingTimeInterval(1 * hour)
		XCTAssertEqual(ProfileExpiry.reminderDates(expires: soon, now: now), [])
		XCTAssertEqual(ProfileExpiry.reminderDates(expires: now.addingTimeInterval(-day), now: now), [])
	}

	func testReminderDateExactlyNowIsSkipped() {
		let expires = now.addingTimeInterval(24 * hour)
		XCTAssertEqual(ProfileExpiry.reminderDates(expires: expires, now: now), [expires.addingTimeInterval(-2 * hour)])
	}

	func testDaysLeft() {
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now.addingTimeInterval(7 * day), now: now), 7)
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now.addingTimeInterval(7 * day - 1), now: now), 6, "rounds down")
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now.addingTimeInterval(23 * hour), now: now), 0)
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now.addingTimeInterval(36 * hour), now: now), 1)
	}

	func testDaysLeftNeverNegative() {
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now, now: now), 0)
		XCTAssertEqual(ProfileExpiry.daysLeft(expires: now.addingTimeInterval(-3 * day), now: now), 0)
	}

	// MARK: TeamBundleID

	func testSignedAddsTheTeamID() {
		XCTAssertEqual(TeamBundleID.signed(original: "com.radio.app", teamID: "ABCDE12345"), "com.radio.app.ABCDE12345")
	}

	func testSignedKeepsAnAlreadySuffixedID() {
		XCTAssertEqual(TeamBundleID.signed(original: "com.radio.app.ABCDE12345", teamID: "ABCDE12345"), "com.radio.app.ABCDE12345")
	}

	func testSignedWithEmptyTeamIsUnchanged() {
		XCTAssertEqual(TeamBundleID.signed(original: "com.radio.app", teamID: ""), "com.radio.app")
	}

	func testSignedNeedsTheDotBeforeTheTeam() {
		XCTAssertEqual(TeamBundleID.signed(original: "com.radioABCDE12345", teamID: "ABCDE12345"), "com.radioABCDE12345.ABCDE12345")
	}

	func testOriginalStripsOneSuffix() {
		XCTAssertEqual(TeamBundleID.original(signed: "com.radio.app.ABCDE12345", teamID: "ABCDE12345"), "com.radio.app")
		XCTAssertEqual(TeamBundleID.original(signed: "com.radio.app.ABCDE12345.ABCDE12345", teamID: "ABCDE12345"), "com.radio.app.ABCDE12345")
	}

	func testOriginalLeavesOtherIDsAlone() {
		XCTAssertEqual(TeamBundleID.original(signed: "com.radio.app", teamID: "ABCDE12345"), "com.radio.app")
		XCTAssertEqual(TeamBundleID.original(signed: "com.radio.app.ABCDE12345", teamID: ""), "com.radio.app.ABCDE12345")
	}

	func testSignedAndOriginalRoundTrip() {
		let signed = TeamBundleID.signed(original: "com.radio.app", teamID: "ABCDE12345")
		XCTAssertEqual(TeamBundleID.original(signed: signed, teamID: "ABCDE12345"), "com.radio.app")
	}
}
