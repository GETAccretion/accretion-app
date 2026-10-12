//
//  InstallServerLog.swift
//  Accretion
//

import Foundation
import Network
import Vapor

/// Accretion: what happened on the local install server during one install, so "iOS didn't ask to
/// install" can say whether iOS never connected, started a secure connection and gave up (it
/// refused the certificate), or asked for files. Also follows the app file transfer and the
/// iPhone's network state, so a transfer that stalls can say where it stopped.
final class InstallServerLog: @unchecked Sendable {
	static let shared = InstallServerLog()

	private let _lock = NSLock()
	private var _handshakeStarted = false
	private var _hello: String??
	private var _requests: [String] = []
	private var _messages: [String] = []

	// app file transfer
	private var _payloadRequests = 0
	private var _payloadRange: String?
	private var _payloadSize: Int64?
	private var _payloadStarted: Date?
	private var _payloadResult: String?

	// network state as iOS reports it
	private let _pathMonitor = NWPathMonitor()
	private var _network = "unknown"
	private var _networkChanges: [String] = []

	init() {
		_pathMonitor.pathUpdateHandler = { [weak self] path in
			self?._networkChanged(Self._describe(path))
		}
		_pathMonitor.start(queue: DispatchQueue(label: "accretion.install.path"))
	}

	func reset() {
		_lock.lock(); defer { _lock.unlock() }
		_handshakeStarted = false
		_hello = nil
		_requests = []
		_messages = []
		_payloadRequests = 0
		_payloadRange = nil
		_payloadSize = nil
		_payloadStarted = nil
		_payloadResult = nil
		_networkChanges = []
	}

	/// iOS asked for the app file (it may ask more than once, or for part of it)
	func payloadRequested(range: String?, size: Int64?) {
		_lock.lock(); defer { _lock.unlock() }
		_payloadRequests += 1
		_payloadRange = range
		_payloadSize = size
		_payloadStarted = Date()
		_payloadResult = nil
	}

	/// The app file finished sending, or the transfer failed
	func payloadFinished(error: Error?) {
		_lock.lock(); defer { _lock.unlock() }
		guard let started = _payloadStarted else { return }
		let seconds = Int(Date().timeIntervalSince(started))
		_payloadResult = error.map { "failed after \(seconds) s: \(String(describing: $0).prefix(200))" }
			?? "sent completely in \(seconds) s"
	}

	private func _networkChanged(_ text: String) {
		_lock.lock(); defer { _lock.unlock() }
		guard text != _network else { return }
		_network = text
		let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
		_networkChanges.append("\(time) \(text)")
		if _networkChanges.count > 6 { _networkChanges.removeFirst() }
	}

	private static func _describe(_ path: NWPath) -> String {
		let status: String
		switch path.status {
		case .satisfied: status = "online"
		case .unsatisfied: status = "no network"
		case .requiresConnection: status = "needs a connection"
		@unknown default: status = "unknown"
		}
		var types: [String] = []
		if path.usesInterfaceType(.wifi) { types.append("Wi-Fi") }
		if path.usesInterfaceType(.cellular) { types.append("cellular") }
		if path.usesInterfaceType(.wiredEthernet) { types.append("wired") }
		if path.usesInterfaceType(.loopback) { types.append("loopback") }
		if path.usesInterfaceType(.other) { types.append("other") }
		return types.isEmpty ? status : "\(status) (\(types.joined(separator: ", ")))"
	}

	/// Plain words for an app file transfer that hasn't finished
	var payloadSummary: String {
		_lock.lock(); defer { _lock.unlock() }
		var lines: [String] = []
		if _payloadRequests == 0 {
			lines.append("App file: iOS hasn't asked for it.")
		} else {
			let size = _payloadSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unknown size"
			let seconds = _payloadStarted.map { Int(Date().timeIntervalSince($0)) } ?? 0
			lines.append("App file (\(size)): asked for \(_payloadRequests) time(s)" + (_payloadRange.map { ", range \($0)" } ?? "") + ".")
			lines.append("Transfer: " + (_payloadResult ?? "not finished after \(seconds) s"))
		}
		lines.append("Network now: \(_network)")
		if !_networkChanges.isEmpty {
			lines.append("Network changes: " + _networkChanges.joined(separator: "; "))
		}
		if let last = _messages.last {
			lines.append("Server: \(last)")
		}
		return lines.joined(separator: "\n")
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
