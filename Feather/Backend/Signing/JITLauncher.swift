//
//  JITLauncher.swift
//  Accretion
//

import UIKit

/// Accretion: "Open with JIT". iOS only allows JIT while a debugger is attached. With a pairing file
/// imported (Settings → JIT) Accretion attaches the device's own debugger itself (`JITEnabler`);
/// otherwise it hands the app to StikDebug, which does the same with its pairing file. Either way the
/// app must be signed with a certificate that allows a debugger (get-task-allow, which development
/// certificates have).
enum JITLauncher {
	/// nil when unknown (no certificate on record)
	static func allowsDebugger(_ cert: CertificatePair?) -> Bool? {
		guard let cert, let profile = Storage.shared.getProvisionFileDecoded(for: cert) else { return nil }
		return (profile.Entitlements?["get-task-allow"]?.value as? Bool) == true
	}

	@MainActor
	static func open(bundleID: String, certificate: CertificatePair?) {
		if allowsDebugger(certificate) == false {
			UIAlertController.showAlertWithCancel(
				title: String.localized("This copy can't use JIT"),
				message: String.localized("It's signed with a certificate that doesn't allow a debugger, so iOS won't turn JIT on. Re-sign it with a development certificate (shown as \"Development\" in Certificates), install it, then use Open with JIT."),
				actions: [
					UIAlertAction(title: String.localized("Try Anyway"), style: .default) { _ in _launch(bundleID) },
				]
			)
			return
		}
		_launch(bundleID)
	}

	@MainActor
	private static func _launch(_ bundleID: String) {
		if JITEnabler.canRunHere {
			_enableHere(bundleID)
		} else {
			_openStikDebug(bundleID)
		}
	}

	// MARK: - Built in

	@MainActor
	private static func _enableHere(_ bundleID: String) {
		Task.detached(priority: .userInitiated) {
			let reachable = JITEnabler.tunnelReachable()
			await MainActor.run { _enableHere(bundleID, tunnelReachable: reachable) }
		}
	}

	/// The socket check above runs off the main thread; everything from here runs on it.
	@MainActor
	private static func _enableHere(_ bundleID: String, tunnelReachable: Bool) {
		guard tunnelReachable else {
			UIAlertController.showAlertWithCancel(
				title: String.localized("Connect LocalDevVPN first"),
				message: String.localized("Open with JIT reaches the phone's own developer services through LocalDevVPN. Connect it (stay on Wi-Fi or Airplane Mode), then try again."),
				actions: [
					UIAlertAction(title: String.localized("Open LocalDevVPN"), style: .default) { _ in
						UIApplication.open("localdevvpn://enable?scheme=accretion")
					},
					UIAlertAction(title: String.localized("Use StikDebug"), style: .default) { _ in _openStikDebug(bundleID) },
				]
			)
			return
		}
		Task.detached(priority: .userInitiated) {
			do {
				_ = try JITEnabler.enable(bundleID: bundleID)
				await MainActor.run { UIApplication.openApp(with: bundleID) }
			} catch {
				await MainActor.run {
					UIAlertController.showAlertWithCancel(
						title: String.localized("JIT didn't turn on"),
						message: error.localizedDescription,
						actions: [
							UIAlertAction(title: String.localized("Use StikDebug"), style: .default) { _ in _openStikDebug(bundleID) },
						]
					)
				}
			}
		}
	}

	// MARK: - StikDebug

	@MainActor
	private static func _openStikDebug(_ bundleID: String) {
		var components = URLComponents()
		components.scheme = "stikjit"
		components.host = "enable-jit"
		components.queryItems = [URLQueryItem(name: "bundle-id", value: bundleID)]
		guard let url = components.url else { return }
		UIApplication.shared.open(url) { opened in
			guard !opened else { return }
			UIAlertController.showAlertWithOk(
				title: String.localized("Set up JIT first"),
				message: String.localized("Import your pairing file in Settings → JIT and connect LocalDevVPN, and Accretion turns JIT on itself. Or install StikDebug and set it up with the same pairing file.")
			)
		}
	}
}
