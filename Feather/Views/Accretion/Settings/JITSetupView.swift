//
//  JITSetupView.swift
//  Accretion
//

import SwiftUI
import NimbleViews
import IDeviceSwift

/// Settings → JIT: what Open with JIT needs to work from inside Accretion (`JITEnabler`), with the
/// pairing-file import and the LocalDevVPN link. The pairing file is the same one Feather's idevice
/// installs use, so importing it here also enables those.
struct JITSetupView: View {
	@Environment(\.scenePhase) private var _scenePhase
	@State private var _hasPairingFile = false
	@State private var _tunnelUp = false
	@State private var _vpnInstalled = false
	@State private var _importing = false
	@State private var _checking = false

	private var _ready: Bool { JITEnabler.isSupported && _hasPairingFile && _tunnelUp }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				_status

				Text(verbatim: String.localized("iOS turns JIT on only in an app a debugger has attached to. With the items below, Accretion attaches the phone's own debugger for a moment when you choose Open with JIT, then lets go. No computer is needed after the pairing file is made."))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)

				_row(
					done: JITEnabler.isSupported,
					String.localized("iOS 17.4 or newer"),
					JITEnabler.isSupported
						? String.localized("This iPhone is fine.")
						: String.localized("On this iOS, Open with JIT hands the app to StikDebug instead.")
				)
				_row(
					done: _hasPairingFile,
					String.localized("Pairing file"),
					_hasPairingFile
						? String.localized("Imported. Make a new one if the phone is restored or re-paired.")
						: String.localized("Made once on a computer with the phone on USB, then imported here.")
				)
				_row(
					done: _tunnelUp,
					String.localized("LocalDevVPN connected"),
					_tunnelUp
						? String.localized("The developer tunnel answers.")
						: String.localized("Free on the App Store. Connect it while enabling JIT; stay on Wi-Fi or Airplane Mode.")
				)
				_row(
					done: nil,
					String.localized("Developer Mode on"),
					String.localized("Settings → Privacy & Security → Developer Mode. Needed for the phone's developer services.")
				)
				_row(
					done: nil,
					String.localized("A development certificate"),
					String.localized("Only certificates that allow a debugger work (shown as \"Development\" in Certificates; a free Apple ID gives one). Sign the app with it before Open with JIT.")
				)

				Button {
					_importing = true
				} label: {
					Text(verbatim: _hasPairingFile ? String.localized("Replace Pairing File") : String.localized("Import Pairing File")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle())

				Button {
					if _vpnInstalled {
						UIApplication.open("localdevvpn://enable?scheme=accretion")
					} else {
						UIApplication.open("https://apps.apple.com/us/app/localdevvpn/id6755608044")
					}
				} label: {
					Text(verbatim: _vpnInstalled ? String.localized("Connect LocalDevVPN") : String.localized("Get LocalDevVPN")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false))

				Button {
					_refresh()
				} label: {
					Text(verbatim: String.localized("Check Again")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
				.disabled(_checking)

				Text(verbatim: String.localized("Making the pairing file: on a computer with the phone plugged in, run pymobiledevice3 (\"pymobiledevice3 lockdown pair\" then \"pymobiledevice3 lockdown save-pair-record\") or Impactor, and send the .plist or .mobiledevicepairing file to this iPhone. Accretion keeps only this one file; nothing else leaves the phone."))
					.accretionFont(12)
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, 8)

				Button {
					UIApplication.open("https://github.com/claration/Impactor#pairing-file")
				} label: {
					Text(verbatim: String.localized("Pairing File Guide")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("JIT"))
		.navigationBarTitleDisplayMode(.inline)
		.onAppear(perform: _refresh)
		.onChange(of: _scenePhase) { phase in
			if phase == .active { _refresh() }
		}
		.sheet(isPresented: $_importing) {
			FileImporterRepresentableView(
				allowedContentTypes: [.xmlPropertyList, .plist, .mobiledevicepairing],
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					FR.movePairing(url)
					_refresh()
				}
			)
			.ignoresSafeArea()
		}
	}

	private var _status: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: _ready ? "bolt.circle.fill" : "exclamationmark.triangle.fill")
				.foregroundStyle(_ready ? AccretionTheme.good : AccretionTheme.warn)
				.accretionFont(18)
			VStack(alignment: .leading, spacing: 3) {
				Text(verbatim: _ready ? String.localized("Ready") : String.localized("Not ready yet"))
					.accretionFont(15, weight: .semibold)
					.foregroundStyle(AccretionTheme.fg)
				Text(verbatim: _ready
					? String.localized("Open with JIT in Library turns JIT on from here.")
					: String.localized("Until everything below is in place, Open with JIT hands the app to StikDebug."))
					.accretionFont(13)
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.accretionCard()
		.accessibilityElement(children: .combine)
	}

	/// `done` nil: a step Accretion can't check itself.
	private func _row(done: Bool?, _ title: String, _ detail: String) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: done == true ? "checkmark.circle.fill" : (done == false ? "circle" : "info.circle"))
				.foregroundStyle(done == true ? AccretionTheme.good : AccretionTheme.muted)
				.accretionFont(16)
				.frame(width: 22)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: title)
					.accretionFont(14, weight: .semibold)
					.foregroundStyle(AccretionTheme.fg)
				Text(verbatim: detail)
					.accretionFont(13)
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.accessibilityElement(children: .combine)
	}

	private func _refresh() {
		_hasPairingFile = JITEnabler.hasPairingFile
		if let url = URL(string: "localdevvpn://") {
			_vpnInstalled = UIApplication.shared.canOpenURL(url)
		}
		guard !_checking else { return }
		_checking = true
		Task.detached(priority: .userInitiated) {
			let up = JITEnabler.tunnelReachable()
			await MainActor.run {
				_tunnelUp = up
				_checking = false
			}
		}
	}
}
