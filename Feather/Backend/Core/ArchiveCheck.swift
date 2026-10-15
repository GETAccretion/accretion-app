import Foundation

/// Accretion: checks an archive's entry list before anything is extracted, so an IPA or .deb from
/// any source can't write outside the folder it is unpacked into (zip-slip), through a symlink it
/// carries, or fill the device (handbook issue #28).
enum ArchiveCheck {
	struct Entry: Equatable {
		let name: String
		let isSymlink: Bool
		let uncompressedSize: UInt64
		let compressedSize: UInt64
	}

	enum Failure: Error, Equatable, LocalizedError {
		case unsafePath(String)
		case throughSymlink(String)
		case tooBig
		case notAZip

		var errorDescription: String? {
			switch self {
			case .unsafePath(let name): return "This file contains a path that points outside the app (\(name)), so it wasn't opened."
			case .throughSymlink(let name): return "This file writes through a link it contains (\(name)), so it wasn't opened."
			case .tooBig: return "This file unpacks to far more than its size, so it wasn't opened."
			case .notAZip: return "This file isn't a valid IPA."
			}
		}
	}

	/// Total unpacked bytes allowed, and how much bigger than the archive that may be.
	static let maxTotal: UInt64 = 8 * 1024 * 1024 * 1024
	static let maxRatio: UInt64 = 100

	/// A relative path that stays inside the destination: no leading "/", no "..", no "\", no NUL.
	static func isSafe(_ name: String) -> Bool {
		guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else { return false }
		return !name.split(separator: "/", omittingEmptySubsequences: true).contains("..")
	}

	static func check(_ entries: [Entry]) throws {
		var links: [String] = []
		var total: UInt64 = 0, packed: UInt64 = 0
		for entry in entries {
			guard isSafe(entry.name) else { throw Failure.unsafePath(entry.name) }
			if entry.isSymlink { links.append(entry.name.hasSuffix("/") ? String(entry.name.dropLast()) : entry.name) }
			total = total.addingReportingOverflow(entry.uncompressedSize).overflow ? .max : total + entry.uncompressedSize
			packed = packed.addingReportingOverflow(entry.compressedSize).overflow ? .max : packed + entry.compressedSize
		}
		for entry in entries where !entry.isSymlink {
			if let link = links.first(where: { entry.name.hasPrefix($0 + "/") }) { throw Failure.throughSymlink(link) }
		}
		if total > maxTotal { throw Failure.tooBig }
		if total > 100 * 1024 * 1024, total / max(packed, 1) > maxRatio { throw Failure.tooBig }
	}

	// MARK: Zip central directory (names, sizes and symlink bits only; nothing is decompressed)

	static func zipEntries(at url: URL) throws -> [Entry] {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		let fileSize = try handle.seekToEnd()
		let tailLength = min(fileSize, 65_557) // end record (22) + longest comment (65535)
		try handle.seek(toOffset: fileSize - tailLength)
		let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
		guard let end = lastIndex(of: 0x0605_4b50, in: tail), end + 22 <= tail.count else { throw Failure.notAZip }

		var count = UInt64(tail.le16(end + 10))
		var size = UInt64(tail.le32(end + 12))
		var offset = UInt64(tail.le32(end + 16))
		if count == 0xFFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
			// ZIP64: the locator sits right before the end record and points at the ZIP64 end record
			guard end >= 20, tail.le32(end - 20) == 0x0706_4b50 else { throw Failure.notAZip }
			let z64 = tail.le64(end - 20 + 8)
			try handle.seek(toOffset: z64)
			let record = try handle.read(upToCount: 56) ?? Data()
			guard record.count == 56, record.le32(0) == 0x0606_4b50 else { throw Failure.notAZip }
			count = record.le64(32)
			size = record.le64(40)
			offset = record.le64(48)
		}
		guard offset <= fileSize, size <= fileSize - offset, size <= 512 * 1024 * 1024 else { throw Failure.notAZip }
		try handle.seek(toOffset: offset)
		let directory = try handle.read(upToCount: Int(size)) ?? Data()
		guard directory.count == Int(size) else { throw Failure.notAZip }

		var entries: [Entry] = []
		var at = 0
		for _ in 0..<count {
			guard at + 46 <= directory.count, directory.le32(at) == 0x0201_4b50 else { throw Failure.notAZip }
			let madeBy = directory.le16(at + 4) >> 8 // 3 = Unix: the high 16 bits of the attributes are the mode
			var packed = UInt64(directory.le32(at + 20))
			var unpacked = UInt64(directory.le32(at + 24))
			let nameLength = Int(directory.le16(at + 28))
			let extraLength = Int(directory.le16(at + 30))
			let commentLength = Int(directory.le16(at + 32))
			let attributes = directory.le32(at + 38)
			let nameStart = at + 46
			guard nameStart + nameLength + extraLength + commentLength <= directory.count else { throw Failure.notAZip }
			let name = String(decoding: directory[nameStart ..< nameStart + nameLength], as: UTF8.self)
			// ZIP64 extra field (id 1): the real sizes when the 32-bit ones are 0xFFFFFFFF
			var extra = nameStart + nameLength
			let extraEnd = extra + extraLength
			while extra + 4 <= extraEnd {
				let id = directory.le16(extra), length = Int(directory.le16(extra + 2))
				if id == 1 {
					var field = extra + 4
					if unpacked == 0xFFFF_FFFF, field + 8 <= extra + 4 + length { unpacked = directory.le64(field); field += 8 }
					if packed == 0xFFFF_FFFF, field + 8 <= extra + 4 + length { packed = directory.le64(field) }
				}
				extra += 4 + length
			}
			let mode = attributes >> 16
			let isSymlink = madeBy == 3 && (mode & 0o170000) == 0o120000
			entries.append(Entry(name: name, isSymlink: isSymlink, uncompressedSize: unpacked, compressedSize: packed))
			at = extraEnd + commentLength
		}
		return entries
	}

	private static func lastIndex(of signature: UInt32, in data: Data) -> Int? {
		guard data.count >= 4 else { return nil }
		var i = data.count - 4
		while i >= 0 {
			if data.le32(i) == signature { return i }
			i -= 1
		}
		return nil
	}
}

private extension Data {
	func le16(_ i: Int) -> UInt16 {
		let b = startIndex + i
		return UInt16(self[b]) | UInt16(self[b + 1]) << 8
	}
	func le32(_ i: Int) -> UInt32 {
		UInt32(le16(i)) | UInt32(le16(i + 2)) << 16
	}
	func le64(_ i: Int) -> UInt64 {
		UInt64(le32(i)) | UInt64(le32(i + 4)) << 32
	}
}
