//
//  JITEnabler.swift
//  Accretion
//

import Foundation
import IDevice
import IDeviceSwift

/// Accretion: turns JIT on for an installed app from inside Accretion, the way StikDebug does it.
///
/// iOS allows JIT only in a process a debugger has attached to. The phone's own developer services
/// are reachable from an app through the loopback tunnel LocalDevVPN provides (10.7.0.1) with the
/// device's pairing file, the same setup Feather's idevice installs use. The enabler launches the app
/// through the developer tunnel, attaches the device's debugserver to it once, and detaches at once.
/// The process keeps the debugged flag until it quits, so JIT stays on while the app runs.
///
/// Needs: iOS 17.4+ (the CoreDevice tunnel), Developer Mode, a pairing file imported into Accretion,
/// LocalDevVPN connected, and an app signed with a certificate that allows a debugger
/// (`get-task-allow`, which development certificates have). Pure FFI into the idevice library the app
/// already ships; nothing here is UI.
enum JITEnabler {
	static let tunnelHost = "10.7.0.1"
	static let tunnelPort: UInt16 = 49152

	enum Failure: LocalizedError {
		case unsupportedIOS
		case noPairingFile
		case pairingFile(String)
		case tunnel(String)
		case developerServices(String)
		case launch(String)
		case debugger(String)
		case attachRefused(String)

		var errorDescription: String? {
			switch self {
			case .unsupportedIOS:
				return String.localized("Built-in JIT needs iOS 17.4 or newer. On this iOS, Open with JIT uses StikDebug.")
			case .noPairingFile:
				return String.localized("No pairing file yet. Import it in Settings → JIT, then try again.")
			case .pairingFile(let detail):
				return String.localized("The pairing file couldn't be read (%@). Make a fresh one on the computer and import it again.", arguments: detail)
			case .tunnel(let detail):
				return String.localized("Couldn't reach the developer tunnel (%@). Connect LocalDevVPN, stay on Wi-Fi or Airplane Mode, check Developer Mode is on, then try again.", arguments: detail)
			case .developerServices(let detail):
				return String.localized("The developer services didn't answer (%@). Check Developer Mode is on, then try again.", arguments: detail)
			case .launch(let detail):
				return String.localized("The app couldn't be launched (%@). Is it still installed?", arguments: detail)
			case .debugger(let detail):
				return String.localized("The debugger couldn't be reached (%@).", arguments: detail)
			case .attachRefused(let detail):
				return String.localized("The debugger couldn't attach (%@). The app must be signed with a certificate that allows a debugger (a development certificate).", arguments: detail)
			}
		}
	}

	/// The CoreDevice tunnel exists from iOS 17.4; older iOS keeps the StikDebug hand-off.
	static var isSupported: Bool {
		if #available(iOS 17.4, *) { return true }
		return false
	}

	/// The pairing file Feather's idevice installs use (`Documents/pairingFile.plist`).
	static var pairingFilePath: String { HeartbeatManager.pairingFile() }

	static var hasPairingFile: Bool { FileManager.default.fileExists(atPath: pairingFilePath) }

	/// Whether the tunnel endpoint answers at all (LocalDevVPN connected). Quick, no pairing needed.
	static func tunnelReachable(timeout: Double = 1.5) -> Bool {
		HeartbeatManager.shared.checkSocketConnection(timeoutInSeconds: timeout).isConnected
	}

	/// Everything Open with JIT needs before it can work on its own.
	static var canRunHere: Bool { isSupported && hasPairingFile }

	/// Launches `bundleID` through the developer tunnel, attaches the debugger once and detaches.
	/// Blocking (several seconds); call it off the main thread. Returns the launched process ID.
	static func enable(bundleID: String) throws -> UInt64 {
		guard isSupported else { throw Failure.unsupportedIOS }
		guard hasPairingFile else { throw Failure.noPairingFile }

		var pairing: OpaquePointer?
		if let err = rp_pairing_file_read(pairingFilePath, &pairing) {
			throw Failure.pairingFile(_consume(err))
		}
		defer { rp_pairing_file_free(pairing) }

		var address = sockaddr_in()
		memset(&address, 0, MemoryLayout<sockaddr_in>.size)
		address.sin_family = sa_family_t(AF_INET)
		address.sin_port = CFSwapInt16HostToBig(tunnelPort)
		guard inet_pton(AF_INET, tunnelHost, &address.sin_addr) == 1 else {
			throw Failure.tunnel("bad tunnel address")
		}

		var adapter: OpaquePointer?
		var handshake: OpaquePointer?
		let tunnelError = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
				tunnel_create_rppairing(
					pointer,
					socklen_t(MemoryLayout<sockaddr_in>.size),
					"Accretion",
					pairing,
					nil,
					nil,
					&adapter,
					&handshake
				)
			}
		}
		if let tunnelError { throw Failure.tunnel(_consume(tunnelError)) }
		defer {
			rsd_handshake_free(handshake)
			adapter_free(adapter)
		}

		// Developer services (DVT) over the tunnel: launch the app, suspended, replacing a running copy.
		var server: OpaquePointer?
		if let err = remote_server_connect_rsd(adapter, handshake, &server) {
			throw Failure.developerServices(_consume(err))
		}
		defer { remote_server_free(server) }

		var control: OpaquePointer?
		if let err = process_control_new(server, &control) {
			throw Failure.developerServices(_consume(err))
		}
		defer { process_control_free(control) }

		var pid: UInt64 = 0
		if let err = process_control_launch_app(control, bundleID, nil, 0, nil, 0, true, true, &pid) {
			throw Failure.launch(_consume(err))
		}
		// Emulators and other JIT apps map large regions; the limit lift is harmless for the rest.
		if let err = process_control_disable_memory_limit(control, pid) { idevice_error_free(err) }

		// debugserver: attach once, then detach. Attaching is what sets the debugged flag.
		var proxy: OpaquePointer?
		if let err = debug_proxy_connect_rsd(adapter, handshake, &proxy) {
			throw Failure.debugger(_consume(err))
		}
		defer { debug_proxy_free(proxy) }

		let attach = try _send("vAttach;" + String(pid, radix: 16), to: proxy)
		// debugserver answers a stop reply (T.. or S..) when attached; E.. when it could not.
		if attach.hasPrefix("E") || attach.isEmpty {
			throw Failure.attachRefused(attach.isEmpty ? "no reply" : attach)
		}
		_ = try _send("D", to: proxy)
		return pid
	}

	// MARK: - Helpers

	private static func _send(_ command: String, to proxy: OpaquePointer?) throws -> String {
		guard let handle = debugserver_command_new(command, nil, 0) else {
			throw Failure.debugger("command")
		}
		defer { debugserver_command_free(handle) }
		var reply: UnsafeMutablePointer<CChar>?
		if let err = debug_proxy_send_command(proxy, handle, &reply) {
			throw Failure.debugger(_consume(err))
		}
		guard let reply else { return "" }
		defer { idevice_string_free(reply) }
		return String(cString: reply)
	}

	/// The error's text, with the error freed.
	private static func _consume(_ error: UnsafeMutablePointer<IdeviceFfiError>) -> String {
		defer { idevice_error_free(error) }
		let message = error.pointee.message.map { String(cString: $0) } ?? ""
		return message.isEmpty ? "code \(error.pointee.code)" : message
	}
}
