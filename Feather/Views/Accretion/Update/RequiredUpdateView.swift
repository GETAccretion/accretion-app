//
//  RequiredUpdateView.swift
//  Accretion
//

import SwiftUI

/// Covers the app while this version is older than the store's minimum (AppPolicy). It can't be
/// dismissed; Get Update fetches the newest Accretion (signing in first when needed).
struct RequiredUpdateView: View {
	@ObservedObject private var _policy = AppPolicy.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@State private var _isSigningIn = false
	@State private var _isWorking = false

	var body: some View {
		VStack(spacing: 18) {
			Spacer()
			Image(systemName: "arrow.down.app.fill")
				.font(.system(size: 56))
				.foregroundStyle(AccretionTheme.accent)
			Text(verbatim: String.localized("Update required"))
				.font(.accretionDisplay(28))
				.foregroundStyle(AccretionTheme.headline)
			Text(verbatim: String.localized(
				"Accretion %@ is no longer supported. Version %@ or newer is needed to keep using the store, downloads and signing.",
				arguments: Bundle.main.version, _policy.minimumVersion ?? ""
			))
			.font(.system(size: 15))
			.foregroundStyle(AccretionTheme.muted)
			.multilineTextAlignment(.center)
			.fixedSize(horizontal: false, vertical: true)

			VStack(spacing: 10) {
				if _account.isSignedIn {
					Button {
						_isWorking = true
						Task {
							await _policy.getUpdate()
							_isWorking = false
						}
					} label: {
						Text(verbatim: _isWorking ? String.localized("Getting update…") : String.localized("Get Update"))
							.frame(maxWidth: .infinity)
					}
					.buttonStyle(AccretionButtonStyle())
					.disabled(_isWorking)
				} else {
					Button { _isSigningIn = true } label: {
						Text(verbatim: String.localized("Sign in to get the update")).frame(maxWidth: .infinity)
					}
					.buttonStyle(AccretionButtonStyle())
				}
				Button {
					Task { await _policy.refresh() }
				} label: {
					Text(verbatim: String.localized("Check again")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
			}
			.padding(.top, 8)

			Text(verbatim: String.localized("Install the update with the tool you used to install Accretion, for example your certificate seller's signer."))
				.font(.system(size: 12))
				.foregroundStyle(AccretionTheme.muted)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
			Spacer()
		}
		.padding(28)
		.frame(maxWidth: 480)
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.accretionBackground()
		.interactiveDismissDisabled()
		.sheet(isPresented: $_isSigningIn) {
			AccountSheet()
		}
	}
}
