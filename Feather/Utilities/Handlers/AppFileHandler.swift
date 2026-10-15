//
//  IPAHandler.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation
import Zip
import SWCompression
import SwiftUI

final class AppFileHandler: NSObject, @unchecked Sendable {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	private let _uniqueWorkDir: URL
	var uniqueWorkDirPayload: URL?

	private var _ipa: URL
	private let _install: Bool
	private let _download: Download?
	private let _sourceProvenance: SourceAppProvenance?
	
	init(
		file ipa: URL,
		install: Bool = false,
		download: Download? = nil,
		sourceProvenance: SourceAppProvenance? = nil
	) {
		self._ipa = ipa
		self._install = install
		self._download = download
		self._sourceProvenance = sourceProvenance ?? download?.sourceProvenance
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherImport_\(_uuid)", isDirectory: true)
		
		super.init()
	}
	
	func copy() async throws {
		try _fileManager.createDirectoryIfNeeded(at: _uniqueWorkDir)
		
		let destinationURL = _uniqueWorkDir.appendingPathComponent(_ipa.lastPathComponent)

		try _fileManager.removeFileIfNeeded(at: destinationURL)
		
		try _fileManager.copyItem(at: _ipa, to: destinationURL)
		_ipa = destinationURL
	}
	
	func extract() async throws {
		if _ipa.pathExtension == "ipa" {
			Zip.addCustomFileExtension("ipa")
		}
		if _ipa.pathExtension == "tipa" {
			Zip.addCustomFileExtension("tipa")
		}
		
		let download = self._download
		try Self._checkEntries(of: _ipa)
		
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .utility).async {
				do {
					try Zip.unzipFile(
						self._ipa,
						destination: self._uniqueWorkDir,
						overwrite: true,
						password: nil,
						progress: { progress in
							if let download = download {
								DispatchQueue.main.async {
									download.unpackageProgress = progress
									
									#if !targetEnvironment(macCatalyst)
									if #available(iOS 26.0, *) {
										BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
									}
									#endif
								}
							}
						}
					)
					
					self.uniqueWorkDirPayload = self._uniqueWorkDir.appendingPathComponent("Payload")
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}
	
	/// Refuses an archive with an entry that would be written outside the extraction folder. An
	/// IPA comes from a source the user added, and Zip writes every entry at destination + name
	/// without looking for "..", so "../Documents/x" would land anywhere in Accretion's container
	/// (zip-slip). The entry names come from the central directory; nothing is written to check them.
	private static func _checkEntries(of archive: URL) throws {
		let data = try Data(contentsOf: archive, options: .mappedIfSafe)
		let names = try ZipContainer.info(container: data).map(\.name)
		if let escaping = ArchiveEntryPath.firstEscaping(names) {
			throw ImportedFileHandlerError.unsafeArchiveEntry(escaping)
		}
	}

	func move() async throws {
		guard let payloadURL = uniqueWorkDirPayload else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		let destinationURL = try await _directory()
		
		guard _fileManager.fileExists(atPath: payloadURL.path) else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		try _fileManager.moveItem(at: payloadURL, to: destinationURL)
		
		try? _fileManager.removeItem(at: _uniqueWorkDir)
	}
	
	func addToDatabase() async throws {
		let app = try await _directory()
		
		guard let appUrl = _fileManager.getPath(in: app, for: "app") else {
			return
		}
		
		let bundle = Bundle(url: appUrl)
		
		Storage.shared.addImported(
			uuid: _uuid,
			source: _sourceProvenance?.sourceRepositoryURL,
			appName: bundle?.name,
			appIdentifier: bundle?.bundleIdentifier,
			appVersion: bundle?.version,
			appIcon: bundle?.iconFileName
		) { _ in }
		
		if let sourceProvenance = _sourceProvenance {
			Storage.shared.addSourceMetadata(
				for: _uuid,
				kind: .imported,
				provenance: sourceProvenance
			)
		}
	}
	
	private func _directory() async throws -> URL {
		// Documents/Feather/Unsigned/\(UUID)
		_fileManager.unsigned(_uuid)
	}
	
	func clean() async throws {
		try _fileManager.removeFileIfNeeded(at: _uniqueWorkDir)
	}
}

private enum ImportedFileHandlerError: LocalizedError {
	case payloadNotFound
	case unsafeArchiveEntry(String)

	var errorDescription: String? {
		switch self {
		case .payloadNotFound:
			return String.localized("The archive has no Payload folder, so it isn't an app.")
		case .unsafeArchiveEntry(let name):
			return String.localized("The archive wasn't imported: it contains \"%@\", which would be written outside the app's folder.", arguments: name)
		}
	}
}
