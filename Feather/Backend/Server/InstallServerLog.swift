//
//  InstallServerLog.swift
//  Accretion
//

import Foundation
import Vapor

/// Accretion: what happened on the local install server during one install, so "iOS didn't ask to
/// install" can say whether iOS never connected, started a secure connection and gave up (it
/// refused the certificate), or asked for files.
final class InstallServerLog: @unchecked Sendable {
	static let shared = InstallServerLog()

	private let _lock = NSLock()
	private var _handshakeStarted = false
	private var _hello: String??
	private var _requests: [String] = []
	private var _messages: [String] = []

	func reset() {
		_lock.lock(); defer { _lock.unlock() }
		_handshakeStarted = false
		_hello = nil
		_requests = []
		_messages = []
	}

	/// A TLS handshake got as far as agreeing keys (called by the server's key log hook)
	func handshake() {
		_lock.lock(); defer { _lock.unlock() }
		_handshakeStarted = true
	}

	/// The first message of a secure connection arrived, naming this host (SNI)
	func hello(_ host: String?) {
		_lock.lock(); defer { _lock.unlock() }
		_hello = .some(host)
	}

	func request(_ path: String) {
		_lock.lock(); defer { _lock.unlock() }
		if _requests.count < 20 { _requests.append(path) }
	}

	func message(_ text: String) {
		_lock.lock(); defer { _lock.unlock() }
		_messages.append(text)
		if _messages.count > 6 { _messages.removeFirst() }
	}

	/// Plain words for the install card
	var summary: String {
		_lock.lock(); defer { _lock.unlock() }
		var lines: [String] = []
		if !_requests.isEmpty {
			lines.append(String.localized("iOS asked the install server for: %@", arguments: _requests.joined(separator: ", ")))
		} else if _handshakeStarted {
			lines.append(String.localized("iOS started a secure connection to the install server but asked for nothing: it didn't accept the certificate."))
		} else if let hello = _hello {
			lines.append(String.localized("iOS connected to the install server (for %@) but stopped at the start of the secure connection.", arguments: hello ?? String.localized("no name")))
		} else {
			lines.append(String.localized("iOS never completed a connection to the install server."))
		}
		if let last = _messages.last {
			lines.append(String.localized("Server: %@", arguments: last))
		}
		return lines.joined(separator: "\n")
	}
}

/// Keeps the install server's own log lines (connection and TLS errors) for InstallServerLog
struct InstallServerLogHandler: LogHandler {
	var metadata: Logger.Metadata = [:]
	var logLevel: Logger.Level = .trace

	subscript(metadataKey key: String) -> Logger.Metadata.Value? {
		get { metadata[key] }
		set { metadata[key] = newValue }
	}

	func log(
		level: Logger.Level,
		message: Logger.Message,
		metadata: Logger.Metadata?,
		source: String,
		file: String,
		function: String,
		line: UInt
	) {
		guard level >= .debug else { return }
		let text = message.description
		// only what explains a failed connection, not routine request lines
		let lowered = text.lowercased()
		guard ["error", "ssl", "tls", "handshake", "certificate", "close", "fail"].contains(where: lowered.contains) else { return }
		InstallServerLog.shared.message(String(text.prefix(300)))
	}
}
