import Foundation

/// Accretion: finding this iPhone's device ID (UDID) for Apple ID signing. iOS sends it after the
/// user installs a "Profile Service" profile; a seller's development profile also lists it.

enum ProfileService {
	/// The XML property list inside a CMS-signed blob (a .mobileprovision, or iOS's profile reply).
	/// Signed, not encrypted, so the plist is there as plain text.
	static func plist(fromSigned data: Data) -> [String: Any]? {
		guard let start = data.range(of: Data("<?xml".utf8)),
		      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
		else { return nil }
		let slice = data.subdata(in: start.lowerBound..<end.upperBound)
		return (try? PropertyListSerialization.propertyList(from: slice, format: nil)) as? [String: Any]
	}

	/// The UDID from iOS's reply to the profile, if it's a well-formed one
	static func udid(fromReply data: Data) -> String? {
		guard let text = plist(fromSigned: data)?["UDID"] as? String else { return nil }
		return normalized(text)
	}

	/// The device in a profile that lists exactly one (a seller's certificate for this iPhone)
	static func onlyDevice(inProfile data: Data) -> String? {
		guard let devices = plist(fromSigned: data)?["ProvisionedDevices"] as? [String], devices.count == 1 else { return nil }
		return normalized(devices[0])
	}

	/// A UDID as Apple writes it, or nil: 40 hex digits (older iPhones), or 8 + "-" + 16 hex digits
	/// (iPhone XS and newer). Spaces around it are dropped; newer ones are upper-cased.
	static func normalized(_ text: String) -> String? {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
		func isHex(_ part: Substring) -> Bool { part.unicodeScalars.allSatisfy { hex.contains($0) } }
		if trimmed.count == 40, isHex(Substring(trimmed)) { return trimmed.lowercased() }
		let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
		if parts.count == 2, parts[0].count == 8, parts[1].count == 16, isHex(parts[0]), isHex(parts[1]) {
			return trimmed.uppercased()
		}
		return nil
	}

	/// The "Profile Service" profile that makes iOS post its UDID to `replyURL`. Installs nothing.
	static func mobileconfig(replyURL: String, identifier: String, uuid: String) -> Data? {
		let profile: [String: Any] = [
			"PayloadContent": [
				"URL": replyURL,
				"DeviceAttributes": ["UDID", "PRODUCT", "VERSION"],
			],
			"PayloadOrganization": "Accretion",
			"PayloadDisplayName": "Accretion: device ID",
			"PayloadDescription": "Sends this iPhone's device ID to Accretion on this iPhone, so your Apple ID can sign apps for it. Nothing stays installed.",
			"PayloadIdentifier": identifier,
			"PayloadUUID": uuid,
			"PayloadVersion": 1,
			"PayloadType": "Profile Service",
		]
		return try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
	}
}
