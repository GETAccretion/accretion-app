import Foundation
import XCTest
@testable import AccretionCore

final class AccretionBuildSelectionTests: XCTestCase {
	private let app = "io.github.getaccretion.Accretion"
	private let builds = [
		AccretionBuildSelection.Build(version: "1.0.30", sha256: "stable"),
		AccretionBuildSelection.Build(version: "1.0.30.1", sha256: "beta"),
		AccretionBuildSelection.Build(version: "1.0.29", sha256: "older"),
	]

	func testStableNeverUsesBetaFingerprint() {
		XCTAssertEqual(AccretionBuildSelection.select(builds, bundleID: app, version: nil)?.sha256, "stable")
		XCTAssertEqual(AccretionBuildSelection.select(builds, bundleID: app, version: "1.0.29")?.sha256, "stable")
	}

	func testExplicitBetaAndMissingBeta() {
		XCTAssertEqual(AccretionBuildSelection.select(builds, bundleID: app, version: "1.0.30.1")?.sha256, "beta")
		XCTAssertNil(AccretionBuildSelection.select(builds, bundleID: app, version: "1.0.30.2"))
	}

	func testExplicitModVersionNeverFallsBackToAnotherBuild() {
		XCTAssertEqual(AccretionBuildSelection.select(builds, bundleID: "com.fixture.mod", version: "1.0.29")?.sha256, "older")
		XCTAssertNil(AccretionBuildSelection.select(builds, bundleID: "com.fixture.mod", version: "missing"))
	}

	func testPersonalURLPreservesRequestedVersionAndReplacesCredentials() throws {
		let base = try XCTUnwrap(URL(string: "https://fixture.supabase.co"))
		let source = try XCTUnwrap(URL(string: "https://fixture.supabase.co/functions/v1/download?app=old&version=1.0.30.1&key=old&av=old"))
		let url = try XCTUnwrap(AccretionBuildSelection.personalURL(base: base, bundleID: app, key: "fictional", source: source, appVersion: "1.0.30"))
		let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
		let values = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
		XCTAssertEqual(values, ["app": app, "version": "1.0.30.1", "key": "fictional", "av": "1.0.30"])
		XCTAssertEqual(url.host, "fixture.supabase.co")
	}

	func testOnlyRealFingerprintsCount() {
		XCTAssertTrue(AccretionBuildSelection.isFingerprint(String(repeating: "a", count: 64)))
		XCTAssertFalse(AccretionBuildSelection.isFingerprint(nil))
		XCTAssertFalse(AccretionBuildSelection.isFingerprint(""))
		XCTAssertFalse(AccretionBuildSelection.isFingerprint(String(repeating: "A", count: 64)), "uppercase is not how the store records it")
		XCTAssertFalse(AccretionBuildSelection.isFingerprint(String(repeating: "g", count: 64)))
		XCTAssertFalse(AccretionBuildSelection.isFingerprint(String(repeating: "a", count: 63)))
	}

	func testUnverifiedBuildIsNeverChosen() {
		let mixed = [
			AccretionBuildSelection.Build(version: "1.0.5", sha256: nil),
			AccretionBuildSelection.Build(version: "1.0.31", sha256: String(repeating: "c", count: 64)),
		]
		let verified = mixed.filter { AccretionBuildSelection.isFingerprint($0.sha256) }
		XCTAssertEqual(AccretionBuildSelection.select(verified, bundleID: app, version: nil)?.version, "1.0.31")
		XCTAssertNil(AccretionBuildSelection.select(verified, bundleID: "com.fixture.mod", version: "1.0.5"), "an old unverified version can't be picked by asking for it")
	}

	func testServerLinksNeedTheKeyOnlyOnce() throws {
		let host = "fixture.supabase.co"
		let bare = try XCTUnwrap(URL(string: "https://fixture.supabase.co/functions/v1/download?app=com.other.app&version=2.1"))
		let keyed = try XCTUnwrap(URL(string: "https://fixture.supabase.co/functions/v1/download?app=com.other.app&version=2.1&key=fictional"))
		let emptyKey = try XCTUnwrap(URL(string: "https://fixture.supabase.co/functions/v1/download?app=com.other.app&key="))
		let elsewhere = try XCTUnwrap(URL(string: "https://source.invalid/functions/v1/download?app=com.other.app"))
		let plain = try XCTUnwrap(URL(string: "http://fixture.supabase.co/functions/v1/download?app=com.other.app"))
		XCTAssertTrue(AccretionBuildSelection.needsKey(bare, host: host))
		XCTAssertTrue(AccretionBuildSelection.needsKey(emptyKey, host: host))
		XCTAssertFalse(AccretionBuildSelection.needsKey(keyed, host: host))
		XCTAssertFalse(AccretionBuildSelection.needsKey(elsewhere, host: host), "another host never gets the key")
		XCTAssertFalse(AccretionBuildSelection.needsKey(plain, host: host), "plain http never gets the key")
		XCTAssertEqual(AccretionBuildSelection.bundleID(in: bare), "com.other.app")
	}

	func testOtherSourceLinkKeepsItsVersionWhenKeyed() throws {
		let base = try XCTUnwrap(URL(string: "https://fixture.supabase.co"))
		let source = try XCTUnwrap(URL(string: "https://fixture.supabase.co/functions/v1/download?app=com.other.app&version=2.1"))
		let url = try XCTUnwrap(AccretionBuildSelection.personalURL(base: base, bundleID: "com.other.app", key: "fictional", source: source, appVersion: "1.0.33"))
		let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
		let values = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
		XCTAssertEqual(values, ["app": "com.other.app", "version": "2.1", "key": "fictional", "av": "1.0.33"])
	}

	func testUnrelatedURLCannotSupplyHostedVersion() throws {
		let base = try XCTUnwrap(URL(string: "https://fixture.supabase.co"))
		let source = try XCTUnwrap(URL(string: "https://other.invalid/ipa?version=1.0.30.1"))
		let url = try XCTUnwrap(AccretionBuildSelection.personalURL(base: base, bundleID: app, key: "fictional", source: source, appVersion: "1.0.30"))
		XCTAssertFalse(url.absoluteString.contains("version="))
	}

	func testOwnBuildDownloadsAreOurAppsOnOurServer() throws {
		let host = "fixture.supabase.co"
		func own(_ link: String) throws -> Bool {
			AccretionBuildSelection.isOwnBuildDownload(try XCTUnwrap(URL(string: link)), host: host)
		}
		XCTAssertTrue(try own("https://fixture.supabase.co/functions/v1/download?app=io.github.getaccretion.Accretion&key=k"))
		XCTAssertTrue(try own("https://fixture.supabase.co/functions/v1/download?app=io.github.accretionmods.swiftradio&version=4.0.0-mod1.0.0"))
		XCTAssertTrue(try own("https://dl.getaccretion.app/download?app=io.github.getaccretion.Accretion"))
		XCTAssertFalse(try own("https://fixture.supabase.co/functions/v1/download?app=com.mojang.minecraftpe&key=k"), "another source's app")
		XCTAssertFalse(try own("https://other.invalid/functions/v1/download?app=io.github.getaccretion.Accretion"), "not our server")
		XCTAssertFalse(try own("https://source.invalid/Accretion.ipa"), "a plain file link")
		XCTAssertFalse(try own("http://dl.getaccretion.app/download?app=io.github.getaccretion.Accretion"), "not https")
		XCTAssertFalse(AccretionBuildSelection.isOwnApp("io.github.getaccretionx.App"))
		XCTAssertFalse(AccretionBuildSelection.isOwnApp(nil))
	}
}
