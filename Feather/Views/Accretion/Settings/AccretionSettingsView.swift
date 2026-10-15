//
//  AccretionSettingsView.swift
//  Accretion
//

import SwiftUI

// MARK: - Settings
/// Accretion's own Settings screen in the store's style: brand header, cards and icon tiles.
/// Every row opens Feather's existing page for that setting, so nothing that works is rebuilt.
struct AccretionSettingsView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	@ObservedObject private var _account = AccretionAccount.shared
	@AppStorage(UpdateManager.autoCheckKey) private var _autoUpdateCheck: Bool = true
	@AppStorage(UpdateManager.autoInstallKey) private var _autoInstallUpdates: Bool = false
	@AppStorage(UpdateManager.betaKey) private var _betaUpdates: Bool = false

	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	private var _selectedCertificate: CertificatePair? {
		_certificates.indices.contains(_storedSelectedCert) ? _certificates[_storedSelectedCert] : nil
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					_header()
					
					_group(String.localized("Account")) {
						_link(
							String.localized("Accretion Account"),
							_account.email ?? String.localized("Sign in to back up your certificates"),
							"person.crop.circle",
							tint: AccretionTheme.accent2
						) { AccretionAccountView() }
					}

					_group(String.localized("Signing")) {
						_certificateRow()
						_divider()
						_link(String.localized("Signing Options"), String.localized("Defaults for every app you sign"), "signature") { ConfigurationView() }
						_divider()
						_link(String.localized("Tweak Library"), String.localized("Tweaks you can add while signing"), "puzzlepiece.extension") { TweakLibraryView() }
					}

					_group(String.localized("Installing")) {
						_link(String.localized("Installation"), String.localized("Server or idevice, SSL certificates"), "arrow.down.app") { InstallationView() }
						_divider()
						_link(String.localized("Archive & Compression"), String.localized("How IPAs are packed"), "archivebox") { ArchiveView() }
						_divider()
						_toggle(String.localized("Check for Updates Automatically"), String.localized("Every source, at most once an hour"), "arrow.triangle.2.circlepath", $_autoUpdateCheck)
						_divider()
						_toggle(String.localized("Update Apps Automatically"), String.localized("Download and sign updates; you just tap Install"), "bolt.badge.automatic", $_autoInstallUpdates)
						_divider()
						_toggle(String.localized("Beta Updates"), String.localized("Get Accretion test builds before everyone else"), "testtube.2", $_betaUpdates)
					}

					_group(String.localized("Look")) {
						_link(String.localized("Appearance"), String.localized("Theme and accent colour"), "paintbrush") { AppearanceView() }
					}

					_group(String.localized("Accretion")) {
						_web(String.localized("Accretion Store"), String.localized("getaccretion.app"), "storefront", "https://getaccretion.app")
						_divider()
						_link(String.localized("Sign Your Own Apps"), String.localized("The step-by-step guide"), "book") { SignGuideView() }
						_divider()
						_link(String.localized("Store Status"), String.localized("Apps, sources and growth"), "chart.bar") { StatusView() }
						_divider()
						_web(String.localized("Accretion Mods"), String.localized("Mods built by Accretion"), "wand.and.stars", "https://github.com/AccretionMods/mods")
						_divider()
						_web(String.localized("Support Accretion"), String.localized("Ko-fi"), "heart", "https://ko-fi.com/getaccretion")
					}

					_group(String.localized("More")) {
						_link(String.localized("About"), String.localized("This build, credits and licences"), "info.circle") { AccretionAboutView() }
						_divider()
						_web(String.localized("Report a Problem"), String.localized("Opens GitHub issues"), "exclamationmark.bubble", "https://github.com/GETAccretion/accretion-app/issues/new/choose")
						_divider()
						_link(String.localized("Reset"), String.localized("Sources, certificates, apps or everything"), "trash", tint: AccretionTheme.warn) { ResetView() }
					}
				}
				.padding(.horizontal, 16)
				.padding(.bottom, 40)
			}
			.accretionBackground()
			.toolbar(.hidden, for: .navigationBar)
		}
		.tint(AccretionTheme.accent)
	}

	// MARK: Pieces
	private func _header() -> some View {
		HStack(spacing: 14) {
			FRAppIconView(size: 64)
			VStack(alignment: .leading, spacing: 4) {
				Text(verbatim: Bundle.main.name)
					.font(.accretionDisplay(26, weight: .heavy))
					.foregroundStyle(AccretionTheme.fg)
				Text(verbatim: String.localized("Every source, pulled into one."))
					.font(.footnote)
					.foregroundStyle(AccretionTheme.muted)
				AccretionBadge(text: "v\(Bundle.main.version)", color: AccretionTheme.link)
			}
			Spacer(minLength: 0)
		}
		.padding(16)
		.accretionCard()
		.padding(.top, 12)
	}

	private func _group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(verbatim: title.uppercased())
				.font(.accretionMono(11))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
				.padding(.leading, 4)
			VStack(spacing: 0) { content() }
				.accretionCard()
		}
	}

	private func _divider() -> some View {
		Rectangle().fill(AccretionTheme.line).frame(height: 1).padding(.leading, 60)
	}

	private func _tile(_ icon: String, _ tint: Color) -> some View {
		Image(systemName: icon)
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(tint)
			.frame(width: 32, height: 32)
			.background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
	}

	private func _label(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color) -> some View {
		HStack(spacing: 12) {
			_tile(icon, tint)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AccretionTheme.fg)
				Text(verbatim: subtitle).font(.caption).foregroundStyle(AccretionTheme.muted).lineLimit(1)
			}
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 11)
		.contentShape(Rectangle())
	}

	private func _link<Destination: View>(
		_ title: String, _ subtitle: String, _ icon: String,
		tint: Color = AccretionTheme.accent,
		@ViewBuilder destination: @escaping () -> Destination
	) -> some View {
		NavigationLink {
			// Feather's settings pages get the store background and list style too
			destination().accretionList()
		} label: {
			HStack(spacing: 0) {
				_label(title, subtitle, icon, tint)
				Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(AccretionTheme.muted).padding(.trailing, 14)
			}
		}
		.buttonStyle(.plain)
	}

	private func _web(_ title: String, _ subtitle: String, _ icon: String, _ url: String) -> some View {
		Button {
			UIApplication.open(url)
		} label: {
			HStack(spacing: 0) {
				_label(title, subtitle, icon, AccretionTheme.accent2)
				Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(AccretionTheme.muted).padding(.trailing, 14)
			}
		}
		.buttonStyle(.plain)
	}

	private func _toggle(_ title: String, _ subtitle: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
		HStack(spacing: 0) {
			_label(title, subtitle, icon, AccretionTheme.good)
			Toggle(title, isOn: isOn).labelsHidden().padding(.trailing, 14) // named for VoiceOver
		}
	}

	/// The certificate signing uses right now, with its expiry and revocation state
	@ViewBuilder
	private func _certificateRow() -> some View {
		let cert = _selectedCertificate
		let subtitle: String = {
			guard let cert else { return String.localized("None yet. Tap to add your certificate.") }
			if cert.revoked { return String.localized("Revoked. Pick another one.") }
			guard let expiration = cert.expiration else { return cert.nickname ?? "" }
			let days = Calendar.current.dateComponents([.day], from: Date(), to: expiration).day ?? 0
			return String.localized("%@ · %@ days left", arguments: cert.nickname ?? String.localized("Certificate"), String(days))
		}()
		let tint: Color = cert == nil || cert?.revoked == true ? AccretionTheme.warn : AccretionTheme.good
		_link(String.localized("Certificates"), subtitle, "checkmark.seal", tint: tint) { CertificatesView() }
	}
}
