//
//  AppleIDView.swift
//  Accretion
//

import SwiftUI

// MARK: - Apple ID
/// Accretion: Settings → Apple ID. Sign in with any Apple ID (a free one signs apps for 7 days),
/// answer the two-factor code, see the team, and choose the anisette server. The password goes
/// only to Apple and is never stored; the session lives in this iPhone's Keychain.
struct AppleIDView: View {
	@StateObject private var _prompts = AppleIDPromptModel()
	@AppStorage(AppleIDClient.customAnisetteKey) private var _customAnisette = ""

	@State private var _session = AppleIDClient.session
	@State private var _email = ""
	@State private var _password = ""
	@State private var _busy = false
	@State private var _message: String?
	@State private var _team: AppleIDTeam?
	@State private var _hasCertificate: Bool?
	@State private var _appIDCount: Int?
	@AppStorage(AppleIDSigning.enabledKey) private var _signApps = false
	@State private var _udid = AppleIDSigning.udid
	@State private var _typedUDID = ""
	@State private var _records = AppleIDSigning.records
	@ObservedObject private var _pipeline = AutoSignPipeline.shared

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				if let session = _session {
					_signedIn(session)
				} else {
					_signIn()
				}
				if let message = _message {
					Text(verbatim: message)
						.font(.footnote)
						.foregroundStyle(AccretionTheme.muted)
				}
				_limits()
				_anisette()
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Apple ID"))
		.navigationBarTitleDisplayMode(.inline)
		.disabled(_busy)
		.overlay { if _busy { ProgressView() } }
		.task { if _session != nil { await _reload() } }
		// leaving the page cancels an open question, so the waiting call never hangs
		.onDisappear { _prompts.answer(.cancel) }
		// no onDismiss: the sheet only closes through an answer (Verify, Text a Code, Cancel)
		.sheet(item: $_prompts.twoFactor) { request in
			AppleIDTwoFactorSheet(request: request) { _prompts.answer($0) }
		}
		.alert(
			String.localized("Replace a certificate?"),
			isPresented: $_prompts.askingRevoke
		) {
			Button(String.localized("Revoke and Make a New One"), role: .destructive) { _prompts.answer(.confirm) }
			Button(String.localized("Cancel"), role: .cancel) { _prompts.answer(.cancel) }
		} message: {
			Text(verbatim: String.localized("This Apple ID already has as many development certificates as Apple allows. Revoking one stops apps signed with it from opening until they are signed again."))
		}
	}

	// MARK: Signed out
	private func _signIn() -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(verbatim: String.localized("Sign in with your Apple ID to sign apps on this iPhone without a certificate. With a free Apple ID, apps last 7 days and can be signed again. Your password goes only to Apple and isn't saved."))
				.font(.subheadline)
				.foregroundStyle(AccretionTheme.muted)
			TextField(String.localized("Apple ID email"), text: $_email)
				.textContentType(.username)
				.keyboardType(.emailAddress)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.padding(12)
				.accretionCard()
			SecureField(String.localized("Password"), text: $_password)
				.textContentType(.password)
				.padding(12)
				.accretionCard()
			Button(String.localized("Sign In")) {
				Task { await _signInTapped() }
			}
			.buttonStyle(AccretionButtonStyle())
			.disabled(_email.trimmingCharacters(in: .whitespaces).isEmpty || _password.isEmpty)
			Text(verbatim: String.localized("Tip: an extra Apple ID just for signing keeps your main account out of it."))
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
		}
	}

	// MARK: Signed in
	@ViewBuilder
	private func _signedIn(_ session: AppleIDKeychain.Session) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: String.localized("Signed in as")).font(.caption).foregroundStyle(AccretionTheme.muted)
				Text(verbatim: session.email).font(.headline).foregroundStyle(AccretionTheme.fg)
			}
			Spacer()
			Button(String.localized("Sign Out")) {
				AppleIDClient.signOut()
				AppleIDSigning.teamID = nil
				_session = nil
				_team = nil
				_hasCertificate = nil
				_appIDCount = nil
				_message = nil
			}
			.buttonStyle(AccretionButtonStyle(prominent: false))
		}
		.padding(14)
		.accretionCard()

		VStack(alignment: .leading, spacing: 8) {
			_fact(String.localized("Team"), _team.map { "\($0.name) · \($0.type)" })
			_fact(String.localized("Accretion certificate"), _hasCertificate.map {
				$0 ? String.localized("Made") : String.localized("Made when you sign your first app")
			})
			_fact(String.localized("App IDs on this team"), _appIDCount.map { String($0) })
		}
		.padding(14)
		.accretionCard()

		Button(String.localized("Refresh")) {
			Task { await _reload() }
		}
		.buttonStyle(AccretionButtonStyle(prominent: false))

		Toggle(isOn: $_signApps) {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: String.localized("Sign Apps with This Apple ID")).accretionFont(15, weight: .semibold)
				Text(verbatim: String.localized("The default on the Signing screen, and used for store installs and updates. Off: choose Apple ID per app under Signing."))
					.font(.caption)
					.foregroundStyle(AccretionTheme.muted)
			}
		}
		.padding(14)
		.accretionCard()

		_device()
		_signedApps()
	}

	// MARK: This iPhone
	@ViewBuilder
	private func _device() -> some View {
		Text(verbatim: String.localized("THIS IPHONE"))
			.font(.accretionMono(11))
			.tracking(1)
			.foregroundStyle(AccretionTheme.muted)
		VStack(alignment: .leading, spacing: 10) {
			if let udid = _udid {
				_fact(String.localized("Device ID"), "…" + String(udid.suffix(6)))
				Button(String.localized("Forget Device ID")) {
					AppleIDSigning.udid = nil
					_udid = AppleIDSigning.udid
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, compact: true))
			} else {
				Text(verbatim: String.localized("Apple needs this iPhone's device ID to sign apps for it. Get it with a profile: Safari downloads it, then install it in Settings → General → VPN & Device Management. It sends the ID back to Accretion and doesn't stay installed."))
					.font(.caption)
					.foregroundStyle(AccretionTheme.muted)
				Button(String.localized("Get Device ID")) {
					do { try AppleIDDeviceServer.shared.open() } catch { _message = error.localizedDescription }
				}
				.buttonStyle(AccretionButtonStyle())
				TextField(String.localized("Or paste the device ID (UDID)"), text: $_typedUDID)
					.textInputAutocapitalization(.characters)
					.autocorrectionDisabled()
					.font(.accretionMono(13, weight: .regular))
					.padding(10)
					.accretionCard()
				Button(String.localized("Save Device ID")) {
					AppleIDSigning.udid = _typedUDID
					_udid = AppleIDSigning.udid
					_message = _udid == nil ? String.localized("That isn't a device ID.") : nil
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, compact: true))
				.disabled(_typedUDID.trimmingCharacters(in: .whitespaces).isEmpty)
			}
		}
		.padding(14)
		.accretionCard()
		.onReceive(NotificationCenter.default.publisher(for: AppleIDSigning.udidFound)) { _ in
			_udid = AppleIDSigning.udid
		}
	}

	// MARK: Signed apps
	@ViewBuilder
	private func _signedApps() -> some View {
		Text(verbatim: String.localized("SIGNED WITH THIS APPLE ID"))
			.font(.accretionMono(11))
			.tracking(1)
			.foregroundStyle(AccretionTheme.muted)
		VStack(alignment: .leading, spacing: 10) {
			if _records.isEmpty {
				Text(verbatim: String.localized("None yet. Sign an app from Library and choose Apple ID under Signing."))
					.font(.caption)
					.foregroundStyle(AccretionTheme.muted)
			}
			ForEach(_records, id: \.bundleID) { record in
				_fact(record.name, record.expires.map { (expires: Date) -> String in
					switch ProfileExpiry.status(expires: expires, now: Date()) {
					case .expired: return String.localized("Expired")
					case .soon, .ok: return String.localized("%@ days left", arguments: String(ProfileExpiry.daysLeft(expires: expires, now: Date())))
					}
				} ?? String.localized("Unknown"))
			}
			Button(_pipeline.status ?? String.localized("Re-sign All")) {
				AutoSignPipeline.shared.resignAll(appleIDOnly: true)
			}
			.buttonStyle(AccretionButtonStyle())
			.disabled(_records.isEmpty || _pipeline.isRunning)
			Text(verbatim: String.localized("Each app gets a fresh 7-day profile. iOS asks to confirm each install."))
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
		}
		.padding(14)
		.accretionCard()
		.onReceive(_pipeline.$status) { status in
			if status == nil { _records = AppleIDSigning.records }
		}
	}

	private func _fact(_ title: String, _ value: String?) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text(verbatim: title).font(.subheadline).foregroundStyle(AccretionTheme.muted)
			Spacer(minLength: 12)
			Text(verbatim: value ?? "…")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(AccretionTheme.fg)
				.multilineTextAlignment(.trailing)
		}
		.accessibilityElement(children: .combine)
	}

	// MARK: Limits and anisette
	private func _limits() -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: String.localized("FREE APPLE ID LIMITS"))
				.font(.accretionMono(11))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: String.localized(
				"Apps last %@ days. At most %@ apps signed this way on this iPhone at a time, and %@ new App IDs a week. App extensions are removed so they don't use App IDs.",
				arguments: String(FreeAccountLimits.profileLifetimeDays),
				String(FreeAccountLimits.maxActiveApps),
				String(FreeAccountLimits.maxNewAppIDsPerWeek)
			))
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
		}
	}

	private func _anisette() -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(verbatim: String.localized("ANISETTE SERVER"))
				.font(.accretionMono(11))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
			TextField(String.localized("Your own server (https://…)"), text: $_customAnisette)
				.keyboardType(.URL)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.padding(12)
				.accretionCard()
			if !_customAnisette.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !AnisetteServers.acceptsCustom(_customAnisette) {
				Text(verbatim: String.localized("This entry is not a full HTTPS URL and is ignored. The default service is used instead."))
					.font(.caption)
					.foregroundStyle(AccretionTheme.muted)
			}
			Text(verbatim: String.localized("Apple needs device details from an anisette service for sign-in. The default is a third-party Mac Anisette service. It receives device-provisioning data, never your Apple ID, password or verification code. Tried in this order:"))
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
			ForEach(Array(AppleIDClient.anisetteServers.enumerated()), id: \.offset) { index, server in
				Text(verbatim: "\(index + 1). \(server.host ?? server.absoluteString)")
					.font(.accretionMono(12, weight: .regular))
					.foregroundStyle(AccretionTheme.fg)
			}
		}
	}

	// MARK: Actions
	private func _signInTapped() async {
		let email = _email.trimmingCharacters(in: .whitespaces)
		let password = _password
		_password = ""
		let prompts = _prompts
		await _work {
			try await AppleIDClient.signIn(email: email, password: password) { prompt in
				await prompts.ask(prompt)
			}
			_session = AppleIDClient.session
			await _reload()
		}
	}

	private func _reload() async {
		await _work {
			let teams = try await AppleIDClient.teams()
			guard let team = teams.first else {
				_message = String.localized("This Apple ID has no developer team.")
				return
			}
			_team = team
			AppleIDSigning.teamID = team.id
			let certificates = try await AppleIDClient.certificates(team: team.id)
			_hasCertificate = certificates.contains { $0.machineName == AppleIDClient.machineName }
			_appIDCount = try await AppleIDClient.appIDs(team: team.id).count
		}
	}

	private func _work(_ action: () async throws -> Void) async {
		_busy = true
		_message = nil
		defer { _busy = false }
		do { try await action() } catch { _message = error.localizedDescription }
	}
}

// MARK: - Prompts
/// Turns the bridge's questions into a sheet (two-factor code) or an alert (revoke a certificate),
/// and hands the answer back to the waiting call.
@MainActor
final class AppleIDPromptModel: ObservableObject {
	struct TwoFactorRequest: Identifiable {
		let id = UUID()
		let bySMS: Bool
		let phones: [AppleIDPrompt.Phone]
	}

	@Published var twoFactor: TwoFactorRequest?
	@Published var askingRevoke = false
	private var _waiting: CheckedContinuation<AppleIDAnswer, Never>?

	func ask(_ prompt: AppleIDPrompt) async -> AppleIDAnswer {
		answer(.cancel) // a question left open is cancelled
		return await withCheckedContinuation { continuation in
			_waiting = continuation
			switch prompt {
			case .twoFactor(let bySMS, let phones):
				twoFactor = TwoFactorRequest(bySMS: bySMS, phones: phones)
			case .revokeCertificate:
				askingRevoke = true
			}
		}
	}

	/// Safe to call more than once
	func answer(_ answer: AppleIDAnswer) {
		twoFactor = nil
		askingRevoke = false
		let waiting = _waiting
		_waiting = nil
		waiting?.resume(returning: answer)
	}
}

/// The six-digit code from a trusted device or a text message
private struct AppleIDTwoFactorSheet: View {
	let request: AppleIDPromptModel.TwoFactorRequest
	let done: (AppleIDAnswer) -> Void
	@State private var _code = ""

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 12) {
				Text(verbatim: request.bySMS
					? String.localized("Enter the code Apple sent by text message.")
					: String.localized("Enter the code shown on your other Apple device."))
					.font(.subheadline)
					.foregroundStyle(AccretionTheme.muted)
				TextField(String.localized("Code"), text: $_code)
					.textContentType(.oneTimeCode)
					.keyboardType(.numberPad)
					.font(.accretionMono(22))
					.padding(12)
					.accretionCard()
				Button(String.localized("Verify")) { done(.code(_code.trimmingCharacters(in: .whitespaces))) }
					.buttonStyle(AccretionButtonStyle())
					.disabled(_code.trimmingCharacters(in: .whitespaces).count < 6)
				if !request.bySMS {
					ForEach(request.phones, id: \.id) { phone in
						Button(String.localized("Text a Code to •••%@", arguments: phone.lastTwo)) {
							done(.sendSMS(phoneID: phone.id))
						}
						.buttonStyle(AccretionButtonStyle(prominent: false))
					}
				}
				Spacer()
			}
			.padding(16)
			.accretionBackground()
			.navigationTitle(String.localized("Two-Factor Code"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String.localized("Cancel")) { done(.cancel) }
				}
			}
		}
		.presentationDetents([.medium])
		.interactiveDismissDisabled()
	}
}
