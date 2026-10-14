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

	func testUnrelatedURLCannotSupplyHostedVersion() throws {
		let base = try XCTUnwrap(URL(string: "https://fixture.supabase.co"))
		let source = try XCTUnwrap(URL(string: "https://other.invalid/ipa?version=1.0.30.1"))
		let url = try XCTUnwrap(AccretionBuildSelection.personalURL(base: base, bundleID: app, key: "fictional", source: source, appVersion: "1.0.30"))
		XCTAssertFalse(url.absoluteString.contains("version="))
	}
}
