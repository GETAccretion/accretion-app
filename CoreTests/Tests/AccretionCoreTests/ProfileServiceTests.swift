import XCTest
@testable import AccretionCore

final class ProfileServiceTests: XCTestCase {
	private let newUDID = "00008140-000E19800A44801C"
	private let oldUDID = "0123456789abcdef0123456789abcdef01234567"

	private func plist(_ body: String) -> String {
		#"<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>"# + body + "</dict></plist>"
	}

	/// The plist wrapped in bytes the way a CMS signature wraps it
	private func signed(_ plist: String) -> Data {
		Data([0x30, 0x82, 0x0B, 0x00, 0x06, 0x09]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x01, 0x00, 0xFF])
	}

	func testReadsTheUDIDFromAReply() {
		let reply = signed(plist("<key>UDID</key><string>\(newUDID)</string><key>PRODUCT</key><string>iPhone17,1</string>"))
		XCTAssertEqual(ProfileService.udid(fromReply: reply), newUDID)
	}

	func testReplyWithoutAValidUDIDGivesNil() {
		XCTAssertNil(ProfileService.udid(fromReply: signed(plist("<key>PRODUCT</key><string>iPhone17,1</string>"))))
		XCTAssertNil(ProfileService.udid(fromReply: signed(plist("<key>UDID</key><string>not-a-udid</string>"))))
		XCTAssertNil(ProfileService.udid(fromReply: Data("no plist here".utf8)))
		XCTAssertNil(ProfileService.udid(fromReply: Data()))
	}

	func testOnlyDeviceNeedsExactlyOne() {
		let one = signed(plist("<key>ProvisionedDevices</key><array><string>\(newUDID)</string></array>"))
		XCTAssertEqual(ProfileService.onlyDevice(inProfile: one), newUDID)
		let two = signed(plist("<key>ProvisionedDevices</key><array><string>\(newUDID)</string><string>\(oldUDID)</string></array>"))
		XCTAssertNil(ProfileService.onlyDevice(inProfile: two))
		XCTAssertNil(ProfileService.onlyDevice(inProfile: signed(plist("<key>Name</key><string>x</string>"))))
	}

	func testNormalizedAcceptsBothFormats() {
		XCTAssertEqual(ProfileService.normalized(newUDID), newUDID)
		XCTAssertEqual(ProfileService.normalized(" 00008140-000e19800a44801c \n"), newUDID)
		XCTAssertEqual(ProfileService.normalized(oldUDID.uppercased()), oldUDID)
	}

	func testNormalizedRejectsOtherText() {
		for bad in ["", "00008140000E19800A44801C", "00008140-000E19800A44801", "0000814-0000E19800A44801C", "00008140-000E19800A44801G", String(oldUDID.dropLast()), "a-b"] {
			XCTAssertNil(ProfileService.normalized(bad), bad)
		}
	}

	func testMobileconfigIsAProfileService() throws {
		let data = try XCTUnwrap(ProfileService.mobileconfig(replyURL: "http://127.0.0.1:5000/udid", identifier: "io.example.udid", uuid: "6F1C3E7A-0000-4000-8000-000000000001"))
		let profile = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
		XCTAssertEqual(profile["PayloadType"] as? String, "Profile Service")
		XCTAssertEqual(profile["PayloadIdentifier"] as? String, "io.example.udid")
		let content = try XCTUnwrap(profile["PayloadContent"] as? [String: Any])
		XCTAssertEqual(content["URL"] as? String, "http://127.0.0.1:5000/udid")
		XCTAssertEqual(content["DeviceAttributes"] as? [String], ["UDID", "PRODUCT", "VERSION"])
	}
}
