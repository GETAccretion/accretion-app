//
//  JITLauncher.swift
//  Accretion
//

import UIKit

/// Accretion: "Open with JIT". iOS only allows JIT while a debugger is attached; StikDebug attaches
/// on the iPhone itself (with its pairing file and LocalDevVPN) and launches the app, picking an
/// iOS 26 script for it when one is needed. The app must be signed with a certificate that allows a
/// debugger (get-task-allow, which development certificates have).
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
		var components = URLComponents()
		components.scheme = "stikjit"
		components.host = "enable-jit"
		components.queryItems = [URLQueryItem(name: "bundle-id", value: bundleID)]
		guard let url = components.url else { return }
		UIApplication.shared.open(url) { opened in
			guard !opened else { return }
			UIAlertController.showAlertWithOk(
				title: String.localized("StikDebug is needed"),
				message: String.localized("Open with JIT hands the app to StikDebug, which turns JIT on. Install StikDebug, set it up with its pairing file and LocalDevVPN, then try again.")
			)
		}
	}
}
