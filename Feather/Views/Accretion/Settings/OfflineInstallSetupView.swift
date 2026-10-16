//
//  OfflineInstallSetupView.swift
//  Accretion
//

import SwiftUI

/// Settings → Installation → Server & SSL → Set Up Offline Installs: installs the certificate this
/// iPhone made (LocalCertificateAuthority) and checks that iOS trusts it.
struct OfflineInstallSetupView: View {
	@Environment(\.scenePhase) private var _scenePhase
	@State private var _trusted = false
	@State private var _name: String?
	@State private var _error: String?
	@State private var _confirmReset = false
	@State private var _outdated = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				_status

				if _outdated {
					VStack(alignment: .leading, spacing: 8) {
						Text(verbatim: String.localized("Renew this certificate"))
							.font(.system(size: 15, weight: .semibold))
							.foregroundStyle(AccretionTheme.fg)
						Text(verbatim: String.localized("It was made by an older Accretion and isn't limited to this iPhone. A new one only works for installs on this iPhone, so it's safer if another app ever reads it. Make a new one, remove the old \"Accretion Offline Installs\" profile, then install and trust the new one (about a minute)."))
							.font(.system(size: 13))
							.foregroundStyle(AccretionTheme.muted)
							.fixedSize(horizontal: false, vertical: true)
						Button {
							LocalCertificateAuthority.reset()
							_refresh()
						} label: {
							Text(verbatim: String.localized("Make a New Certificate")).frame(maxWidth: .infinity)
						}
						.buttonStyle(AccretionButtonStyle())
					}
					.padding(12)
					.accretionCard()
				}

				Text(verbatim: String.localized("Offline installs use a certificate made on this iPhone. Its key never leaves the device. Set it up once:"))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)

				if !_trusted {
					Text(verbatim: String.localized("Set this up before, then deleted Accretion or moved to a new iPhone? First remove the old \"Accretion Offline Installs\" profile in Settings → General → VPN & Device Management. It can't be used any more."))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.warn)
						.fixedSize(horizontal: false, vertical: true)
				}

				_step(1, String.localized("Tap Install Profile. Safari opens and iOS says the profile was downloaded. Come back here."))
				_step(2, String.localized("Open Settings → General → VPN & Device Management, tap \"Accretion Offline Installs\" and install it."))
				_step(3, String.localized("Open Settings → General → About → Certificate Trust Settings and turn on %@.", arguments: _name ?? String.localized("the Accretion Local Install certificate")))
				_step(4, String.localized("Come back and tap Check Again."))

				Button {
					do {
						try LocalCertificateProfileServer.shared.open()
						_error = nil
					} catch {
						_error = error.localizedDescription
					}
				} label: {
					Text(verbatim: String.localized("Install Profile")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle())

				Button {
					_refresh()
				} label: {
					Text(verbatim: String.localized("Check Again")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false))

				if let _error {
					Text(verbatim: _error)
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.warn)
						.fixedSize(horizontal: false, vertical: true)
				}

				Button(role: .destructive) {
					_confirmReset = true
				} label: {
					Text(verbatim: String.localized("Make a New Certificate")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
				.padding(.top, 12)

				Text(verbatim: String.localized("Only needed if something went wrong. The old profile stops working: remove it in Settings → General → VPN & Device Management, then set up again."))
					.font(.system(size: 12))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Offline Installs"))
		.navigationBarTitleDisplayMode(.inline)
		.onAppear(perform: _refresh)
		.onChange(of: _scenePhase) { phase in
			if phase == .active { _refresh() }
		}
		.confirmationDialog(String.localized("Make a new certificate?"), isPresented: $_confirmReset, titleVisibility: .visible) {
			Button(String.localized("Make a New Certificate"), role: .destructive) {
				LocalCertificateAuthority.reset()
				_refresh()
			}
		} message: {
			Text(verbatim: String.localized("You'll need to install and trust the new profile again."))
		}
	}

	private var _status: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: _trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
				.foregroundStyle(_trusted ? AccretionTheme.good : AccretionTheme.warn)
				.font(.system(size: 18))
			VStack(alignment: .leading, spacing: 3) {
				Text(verbatim: _trusted ? String.localized("Ready") : String.localized("Not set up yet"))
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(AccretionTheme.fg)
				Text(verbatim: _trusted
					? String.localized("iOS trusts this iPhone's install certificate. Installs work without the internet.")
					: String.localized("iOS doesn't trust this iPhone's install certificate yet. Follow the steps below."))
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.accretionCard()
		.accessibilityElement(children: .combine)
	}

	private func _step(_ number: Int, _ text: String) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Text(verbatim: "\(number)")
				.font(.system(size: 13, weight: .bold))
				.foregroundStyle(AccretionTheme.fg)
				.frame(width: 22, height: 22)
				.background(Circle().fill(AccretionTheme.line))
			Text(verbatim: text)
				.font(.system(size: 14))
				.foregroundStyle(AccretionTheme.fg)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func _refresh() {
		do {
			try LocalCertificateAuthority.prepare()
			_error = nil
		} catch {
			_error = error.localizedDescription
		}
		_name = LocalCertificateAuthority.displayName
		_outdated = LocalCertificateAuthority.isCreated && !LocalCertificateAuthority.isLimitedToThisDevice
		_trusted = LocalCertificateAuthority.isTrusted
	}
}
