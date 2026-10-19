//
//  SignGuideView.swift
//  Accretion
//

import SwiftUI

// MARK: - Support links (the store's support.json)
/// Certificate sellers and the donation link, from the same support.json the website reads.
/// Sellers are affiliate links; each part stays hidden until it's filled in.
@MainActor
final class SupportLinks: ObservableObject {
	static let shared = SupportLinks()

	struct Seller: Decodable, Identifiable, Hashable {
		let name: String
		let url: String
		let note: String?
		var id: String { url }
		var link: URL? { URL(string: url).flatMap { $0.scheme == "https" ? $0 : nil } }
	}

	@Published private(set) var sellers: [Seller] = []
	@Published private(set) var kofi: URL?
	private var _loadedAt: Date?

	private struct _File: Decodable {
		let kofi: String?
		let certificates: [Seller]?
	}

	func load() async {
		if let loaded = _loadedAt, Date().timeIntervalSince(loaded) < 3600 { return }
		guard
			let (data, _) = try? await URLSession.shared.data(from: StoreService.base.appendingPathComponent("support.json")),
			let file = try? JSONDecoder().decode(_File.self, from: data)
		else {
			return
		}
		sellers = (file.certificates ?? []).filter { $0.link != nil }
		kofi = file.kofi.flatMap(URL.init(string:))
		_loadedAt = Date()
	}
}

// MARK: - Certificate line
/// "Need a signing certificate? Shop · Shop · affiliate" under the install buttons
struct CertificateLine: View {
	@ObservedObject private var _support = SupportLinks.shared
	@Environment(\.openURL) private var _openURL

	var body: some View {
		if !_support.sellers.isEmpty {
			AccretionFlow(spacing: 6) {
				Text(verbatim: String.localized("Need a signing certificate?"))
					.foregroundStyle(AccretionTheme.muted)
				ForEach(_support.sellers) { seller in
					Button { if let link = seller.link { _openURL(link) } } label: {
						Text(verbatim: seller.name).underline()
					}
					.buttonStyle(.plain)
					.foregroundStyle(AccretionTheme.link)
				}
				Text(verbatim: "· " + String.localized("affiliate"))
					.foregroundStyle(AccretionTheme.muted)
			}
			.accretionFont(13)
		}
	}
}

// MARK: - Sign your own apps
/// Navigation value for the guide (Discover and app pages push it)
struct SignGuideRoute: Hashable {}

/// The website's #/sign guide, for the app: get a certificate, add it, pick an app, customise,
/// and what to do when something goes wrong.
struct SignGuideView: View {
	@ObservedObject private var _support = SupportLinks.shared
	@Environment(\.openURL) private var _openURL

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				Text(verbatim: String.localized("Sign your own apps"))
					.font(.accretionDisplay(28))
					.foregroundStyle(AccretionTheme.headline)
					.padding(.top, 6)
				Text(verbatim: String.localized("Install any app on your iPhone, even one that isn't in the store yet, or your own IPA. No computer and no 7-day limit: Accretion signs it on your phone with your certificate."))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)

				_step(1, String.localized("Get a certificate")) {
					_text(String.localized("A paid certificate (a .p12 file, a .mobileprovision file and a password) installs apps for about a year without a computer."))
					if _support.sellers.isEmpty {
						_text(String.localized("Pick a seller that replaces or refunds certificates Apple revokes."))
					} else {
						ForEach(_support.sellers) { seller in
							HStack(spacing: 10) {
								VStack(alignment: .leading, spacing: 2) {
									Text(verbatim: seller.name).accretionFont(15, weight: .semibold).foregroundStyle(AccretionTheme.fg)
									if let note = seller.note, !note.isEmpty {
										Text(verbatim: note).accretionFont(13).foregroundStyle(AccretionTheme.muted)
									}
								}
								Spacer(minLength: 0)
								Button(String.localized("Get certificate")) { if let link = seller.link { _openURL(link) } }
									.buttonStyle(AccretionButtonStyle(prominent: false, compact: true))
							}
							.padding(12)
							.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
						}
						_text(String.localized("Affiliate links: Accretion earns a commission, at no extra cost to you."))
					}
					_text(String.localized("Free alternative: AltStore or SideStore with your own Apple ID (needs a computer once, apps refresh every 7 days)."))
				}

				_step(2, String.localized("Add it to Accretion")) {
					_text(String.localized("Settings → Certificates → +, then pick the .p12 and .mobileprovision files and type the password. Your files stay on this iPhone."))
					_text(String.localized("Signed in? Settings → Account backs your certificate up to your account, sealed with a passphrase, so you can restore it on a new iPhone."))
				}

				_step(3, String.localized("Pick an app")) {
					_text(String.localized("In Discover, open any app and tap Install. Accretion downloads it, signs it with your certificate and asks iOS to install it."))
					_text(String.localized("Already have an IPA? Open it from Files or Safari downloads, tap Share and pick Accretion, or use Library → Import."))
				}

				_step(4, String.localized("Customize before installing (optional)")) {
					_tip(String.localized("New app name"), String.localized("Name"))
					_tip(String.localized("Install a second copy"), String.localized("Identifier"))
					_tip(String.localized("Custom app icon"), String.localized("Customization"))
					_tip(String.localized("Install on an older iOS"), String.localized("Advanced → Properties → Minimum Requirement"))
					_tip(String.localized("Browse the app's files"), String.localized("File Sharing"))
					_tip(String.localized("Remove PlugIns"), String.localized("Advanced → Modify → Frameworks & PlugIns"))
					_tip(String.localized("Add tweaks (.dylib, .deb)"), String.localized("Advanced → Modify → Tweaks"))
					_text(String.localized("Turn on Remember for This App and updates keep your changes."))
				}

				AccretionSection(String.localized("If something goes wrong")) {
					_faq(String.localized("The app won't open"), String.localized("Apple probably revoked the certificate. Accretion warns you when it notices; import a new one and use Re-sign All in Library's ✨ menu."))
					_faq(String.localized("iOS says the integrity couldn't be verified"), String.localized("Usually app extensions a single-app certificate can't cover. Accretion leaves them out automatically; update to the newest Accretion."))
					_faq(String.localized("It fails to sign"), String.localized("Try removing PlugIns (Advanced → Modify → Frameworks & PlugIns), or check the certificate hasn't expired."))
					_faq(String.localized("Nothing happens after Install"), String.localized("Wait a few seconds for iOS to ask. If it never does, check Settings → Installation, or switch off iCloud Private Relay and try again."))
				}

				if let kofi = _support.kofi {
					Button { _openURL(kofi) } label: {
						Text(verbatim: "♥ " + String.localized("Accretion is free and ad-free. Support it")).underline()
					}
					.buttonStyle(.plain)
					.accretionFont(13)
					.foregroundStyle(AccretionTheme.link)
					.padding(.top, 4)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.accretionNavigationBar(String.localized("Sign your own apps"))
		.task { await _support.load() }
	}

	private func _step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 10) {
				Text(verbatim: "\(number)")
					.font(.accretionMono(14, weight: .bold))
					.foregroundStyle(Color.white)
					.frame(width: 28, height: 28)
					.background(AccretionTheme.accentFill, in: Circle())
				Text(verbatim: title)
					.font(.accretionDisplay(18))
					.foregroundStyle(AccretionTheme.fg)
			}
			content()
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.accretionCard()
	}

	private func _text(_ text: String) -> some View {
		Text(verbatim: text)
			.accretionFont(15)
			.foregroundStyle(AccretionTheme.fg)
			.fixedSize(horizontal: false, vertical: true)
	}

	private func _tip(_ what: String, _ where_: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: what).accretionFont(15).foregroundStyle(AccretionTheme.fg)
			Text(verbatim: where_).font(.accretionMono(12, weight: .regular)).foregroundStyle(AccretionTheme.accentText)
		}
	}

	private func _faq(_ question: String, _ answer: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: question).accretionFont(15, weight: .semibold).foregroundStyle(AccretionTheme.fg)
			Text(verbatim: answer).accretionFont(14).foregroundStyle(AccretionTheme.muted).fixedSize(horizontal: false, vertical: true)
		}
		.padding(.bottom, 6)
	}
}
