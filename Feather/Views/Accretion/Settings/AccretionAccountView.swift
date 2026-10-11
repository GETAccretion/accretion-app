//
//  AccretionAccountView.swift
//  Accretion
//

import SwiftUI

// MARK: - Account
/// Settings → Accretion Account: sign in with your store account and back up or restore
/// certificates, sealed with a passphrase only you know.
struct AccretionAccountView: View {
	@ObservedObject private var _account = AccretionAccount.shared

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>

	@State private var _email = ""
	@State private var _password = ""
	@State private var _busy = false
	@State private var _providers: [AccretionAccount.Provider] = []
	@State private var _message: String?
	@State private var _backups: [AccretionAccount.Backup] = []
	@State private var _passphraseFor: PassphraseRequest?

	enum PassphraseRequest: Identifiable {
		case backUp
		case restore(AccretionAccount.Backup)
		var id: String {
			switch self {
			case .backUp: return "backup"
			case .restore(let backup): return backup.id
			}
		}
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				if _account.isSignedIn {
					_signedIn()
				} else {
					_signIn()
				}
				if let message = _message {
					Text(verbatim: message)
						.font(.footnote)
						.foregroundStyle(AccretionTheme.muted)
				}
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Accretion Account"))
		.navigationBarTitleDisplayMode(.inline)
		.disabled(_busy)
		.overlay { if _busy { ProgressView() } }
		.task { if _account.isSignedIn { await _reload() } }
		.sheet(item: $_passphraseFor) { request in
			PassphraseSheet(confirm: { if case .backUp = request { return true } else { return false } }()) { passphrase in
				_passphraseFor = nil
				Task { await _run(request, passphrase: passphrase) }
			}
		}
	}

	// MARK: Signed out
	private func _signIn() -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Color.clear.frame(height: 0).task { _providers = await _account.enabledProviders() }
			Text(verbatim: String.localized("Sign in with your Accretion store account to back up your certificates. They're sealed on this iPhone with a passphrase only you know before anything is uploaded."))
				.font(.subheadline)
				.foregroundStyle(AccretionTheme.muted)
			if !_providers.isEmpty {
				ForEach(_providers) { provider in
					Button(String.localized("Continue with %@", arguments: provider.title)) {
						Task {
							await _work {
								try await _account.signIn(with: provider)
								await _reload()
							}
						}
					}
					.buttonStyle(AccretionButtonStyle(prominent: false))
					.frame(maxWidth: .infinity)
				}
				Text(verbatim: String.localized("or with email"))
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
					.frame(maxWidth: .infinity)
			}
			TextField(String.localized("Email"), text: $_email)
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
				Task {
					await _work {
						try await _account.signIn(email: _email.trimmingCharacters(in: .whitespaces), password: _password)
						_password = ""
						await _reload()
					}
				}
			}
			.buttonStyle(AccretionButtonStyle())
			.disabled(_email.isEmpty || _password.isEmpty)
			Button(String.localized("No account? Create one on the website")) {
				UIApplication.open("https://getaccretion.github.io/")
			}
			.font(.footnote)
		}
	}

	// MARK: Signed in
	@ViewBuilder
	private func _signedIn() -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: String.localized("Signed in as")).font(.caption).foregroundStyle(AccretionTheme.muted)
				Text(verbatim: _account.email ?? "").font(.headline).foregroundStyle(AccretionTheme.fg)
			}
			Spacer()
			Button(String.localized("Sign Out")) {
				_account.signOut()
				_backups = []
			}
			.buttonStyle(AccretionButtonStyle(prominent: false))
		}
		.padding(14)
		.accretionCard()

		Button {
			_passphraseFor = .backUp
		} label: {
			Label(String.localized("Back Up Certificates (%@)", arguments: String(_certificates.count)), systemImage: "icloud.and.arrow.up")
		}
		.buttonStyle(AccretionButtonStyle())
		.disabled(_certificates.isEmpty)

		Text(verbatim: String.localized("BACKUPS"))
			.font(.accretionMono(11))
			.tracking(1)
			.foregroundStyle(AccretionTheme.muted)

		if _backups.isEmpty {
			Text(verbatim: String.localized("No backups yet."))
				.font(.footnote)
				.foregroundStyle(AccretionTheme.muted)
		}
		ForEach(_backups) { backup in
			HStack(spacing: 12) {
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: backup.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(AccretionTheme.fg)
					Text(verbatim: [
						backup.expires.map { String.localized("expires %@", arguments: String($0.prefix(10))) },
						String.localized("saved %@", arguments: String(backup.created_at.prefix(10))),
					].compactMap { $0 }.joined(separator: " · "))
						.font(.caption)
						.foregroundStyle(AccretionTheme.muted)
				}
				Spacer()
				Button(String.localized("Restore")) { _passphraseFor = .restore(backup) }
					.buttonStyle(AccretionButtonStyle(prominent: false))
				Button {
					ConfirmDelete.ask(String.localized("Delete this backup?"), message: String.localized("It's removed from your account for good.")) {
						Task { await _work { try await _account.deleteBackup(backup.id); await _reload() } }
					}
				} label: {
					Image(systemName: "trash")
				}
				.foregroundStyle(AccretionTheme.warn)
				.accessibilityLabel(String.localized("Delete backup"))
			}
			.padding(12)
			.accretionCard()
		}

		Text(verbatim: String.localized("Backups are sealed with your passphrase before upload. Accretion can't read them or recover a lost passphrase."))
			.font(.caption)
			.foregroundStyle(AccretionTheme.muted)
	}

	// MARK: Actions
	private func _run(_ request: PassphraseRequest, passphrase: String) async {
		switch request {
		case .backUp:
			await _work {
				let count = try await _account.backUp(Array(_certificates), passphrase: passphrase)
				await _reload()
				_message = String.localized("%@ certificates backed up.", arguments: String(count))
			}
		case .restore(let backup):
			await _work {
				try await _account.restore(backup, passphrase: passphrase)
				_message = String.localized("%@ restored. Find it in Settings → Certificates.", arguments: backup.label)
			}
		}
	}

	private func _reload() async {
		_backups = (try? await _account.backups()) ?? []
	}

	private func _work(_ action: () async throws -> Void) async {
		_busy = true
		_message = nil
		defer { _busy = false }
		do { try await action() } catch { _message = error.localizedDescription }
	}
}

// MARK: - Passphrase
/// Asks for the backup passphrase; backing up asks twice so a typo can't lock you out.
private struct PassphraseSheet: View {
	let confirm: Bool
	let done: (String) -> Void
	@Environment(\.dismiss) private var _dismiss
	@State private var _first = ""
	@State private var _second = ""

	private var _valid: Bool { _first.count >= 8 && (!confirm || _first == _second) }

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 12) {
				Text(verbatim: confirm
					? String.localized("Choose a passphrase of at least 8 characters. You'll need it to restore; it can't be recovered.")
					: String.localized("Enter the passphrase you chose for this backup."))
					.font(.subheadline)
					.foregroundStyle(AccretionTheme.muted)
				SecureField(String.localized("Passphrase"), text: $_first)
					.padding(12)
					.accretionCard()
				if confirm {
					SecureField(String.localized("Repeat passphrase"), text: $_second)
						.padding(12)
						.accretionCard()
				}
				Button(confirm ? String.localized("Back Up") : String.localized("Restore")) { done(_first) }
					.buttonStyle(AccretionButtonStyle())
					.disabled(!_valid)
				Spacer()
			}
			.padding(16)
			.accretionBackground()
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(String.localized("Cancel")) { _dismiss() }
				}
			}
		}
		.presentationDetents([.medium])
	}
}
