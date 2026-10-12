//
//  LiveContainer.swift
//  Accretion
//

import SwiftUI
import IDeviceSwift

// MARK: - LiveContainer
/// LiveContainer (open source) runs apps inside itself, so they all share its one signature.
/// That's the way around single-App-ID certificates: sign LiveContainer once, then put as many
/// apps in it as you like. Apps that need extensions, push or some system features may not fully
/// work inside it.
enum LiveContainer {
	/// `livecontainer://` is listed in LSApplicationQueriesSchemes so this can be checked.
	static var isInstalled: Bool {
		guard let url = URL(string: "livecontainer://") else { return false }
		return UIApplication.shared.canOpenURL(url)
	}

	/// LiveContainer downloads and installs the IPA itself (its documented install link).
	static func install(from ipa: URL) {
		var components = URLComponents(string: "livecontainer://install")!
		components.queryItems = [URLQueryItem(name: "url", value: ipa.absoluteString)]
		guard let link = components.url else { return }
		if isInstalled {
			UIApplication.shared.open(link)
		} else {
			_offerDownload()
		}
	}

	/// For apps already in Library: packs the IPA and opens the share sheet, where LiveContainer
	/// appears as a destination ("Copy to LiveContainer").
	@MainActor
	static func share(_ app: AppInfoPresentable) {
		Task {
			do {
				let handler = ArchiveHandler(app: app, viewModel: InstallerStatusViewModel(isIdevice: false))
				try await handler.move()
				let package = try await handler.archive()
				guard let ipa = try await handler.moveToArchive(package, shouldOpen: false) else { return }
				UIActivityViewController.show(activityItems: [ipa])
			} catch {
				UIAlertController.showAlertWithOk(
					title: String.localized("Couldn't prepare the IPA"),
					message: error.localizedDescription
				)
			}
		}
	}

	private static func _offerDownload() {
		UIAlertController.showAlertWithCancel(
			title: String.localized("LiveContainer isn't installed"),
			message: String.localized("LiveContainer runs apps inside itself, so a certificate that covers one app can hold many. Install it once with your certificate, then try again."),
			actions: [
				UIAlertAction(title: String.localized("Get LiveContainer"), style: .default) { _ in
					UIApplication.open("https://github.com/LiveContainer/LiveContainer/releases/latest")
				}
			]
		)
	}
}
