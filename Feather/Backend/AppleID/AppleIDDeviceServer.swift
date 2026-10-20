//
//  AppleIDDeviceServer.swift
//  Accretion
//

import Foundation
import Vapor
import UIKit

// MARK: - Device ID profile
/// Accretion: gets this iPhone's device ID (UDID) for Apple ID signing. Serves a "Profile Service"
/// profile on 127.0.0.1 and opens it in Safari; after the user installs it in Settings, iOS posts the
/// device ID back here and nothing stays installed. Runs for 5 minutes, kept alive in the background.
final class AppleIDDeviceServer {
	static let shared = AppleIDDeviceServer()
	private var _app: Application?
	private var _task: UIBackgroundTaskIdentifier = .invalid

	@MainActor
	func open() throws {
		stop()
		let host = LocalCertificateAuthority.loopback
		let port = Int.random(in: 4000...8000)
		let base = "http://\(host):\(port)"
		guard let profile = ProfileService.mobileconfig(
			replyURL: "\(base)/udid",
			identifier: "io.github.getaccretion.Accretion.device-id",
			uuid: UUID().uuidString
		) else { throw CocoaError(.fileWriteUnknown) }

		let app = Application(ServerInstaller.env)
		app.threadPool = .init(numberOfThreads: 1)
		app.http.server.configuration.hostname = host
		app.http.server.configuration.address = .hostname(host, port: port)
		app.http.server.configuration.port = port
		app.get("accretion-device.mobileconfig") { _ in
			Response(
				status: .ok,
				headers: ["Content-Type": "application/x-apple-aspen-config"],
				body: .init(data: profile)
			)
		}
		app.on(.POST, "udid", body: .collect(maxSize: "256kb")) { request -> Response in
			if let buffer = request.body.data, let udid = ProfileService.udid(fromReply: Data(buffer.readableBytesView)) {
				AppleIDSigning.udid = udid
				DispatchQueue.main.async {
					NotificationCenter.default.post(name: AppleIDSigning.udidFound, object: nil)
				}
			}
			// iOS follows this after the reply: back to Accretion
			return Response(status: .movedPermanently, headers: ["Location": "accretion://appleid-device"])
		}
		do {
			try app.server.start()
		} catch {
			app.shutdown()
			throw error
		}
		_app = app
		_task = UIApplication.shared.beginBackgroundTask { [weak self] in self?.stop() }
		DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in self?.stop() }
		if let url = URL(string: "\(base)/accretion-device.mobileconfig") {
			UIApplication.shared.open(url)
		}
	}

	func stop() {
		if let app = _app {
			_app = nil
			app.server.shutdown()
			app.shutdown()
		}
		if _task != .invalid {
			UIApplication.shared.endBackgroundTask(_task)
			_task = .invalid
		}
	}
}
