import Foundation

/// Accretion: the store's download server explains a refusal in its reply body
/// ({"message": "Too many downloads. Try again in a few minutes."}). This reads that sentence so
/// the app can show it instead of a bare status code. Anything else (not JSON, too long, empty) is nil.
enum ServerMessage {
	static func from(_ data: Data?) -> String? {
		guard let data, data.count <= 4096,
		      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
		      !message.isEmpty, message.count <= 300
		else { return nil }
		return message
	}

	static func from(fileAt url: URL) -> String? {
		guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int, size <= 4096 else { return nil }
		return from(try? Data(contentsOf: url))
	}
}
