//
//  AccretionAboutView.swift
//  Accretion
//

import SwiftUI

// MARK: - About
/// Settings → About in the store's style: what this build is (version, build, update channel, device,
/// with one tap to copy it for a bug report), Accretion's links, and the credits and licences it owes.
/// Accretion is a fork of Feather (GPL-3.0): Feather's authors and the licence stay on this page.
struct AccretionAboutView: View {
	@AppStorage(UpdateManager.betaKey) private var _betaUpdates: Bool = false
	@State private var _copied = false
	@ObservedObject private var _consent = AdConsent.shared // Accretion: shows "Privacy choices" when Google requires it

	private struct Credit: Hashable {
		let name: String
		let role: String
		let github: String
	}

	private struct Library: Hashable {
		let name: String
		let note: String
		let url: String
	}

	/// Who made Accretion itself
	private let _accretionCredits: [Credit] = [
		.init(name: "Accretion", role: String.localized("Accretion app, store, community and mods"), github: "GETAccretion"),
	]

	/// Who made Feather, the open-source app Accretion is built on. They don't work on Accretion.
	private let _featherCredits: [Credit] = [
		.init(name: "claration", role: String.localized("Feather: author and maintainer"), github: "claration"),
		.init(name: "Asami", role: String.localized("Feather: developer"), github: "Nyasami"),
		.init(name: "Lakhan Lothiyi", role: String.localized("Feather: AltStore repository support"), github: "llsc12"),
	]

	private let _libraries: [Library] = [
		.init(name: "Zsign", note: "khcrysalis", url: "https://github.com/khcrysalis/Zsign-Package"),
		.init(name: "IDeviceKit", note: "khcrysalis", url: "https://github.com/khcrysalis/IDeviceKit"),
		.init(name: "NimbleKit · AltSourceKit", note: "claration", url: "https://github.com/claration/Feather"),
		.init(name: "Vapor", note: "vapor", url: "https://github.com/vapor/vapor"),
		.init(name: "SwiftNIO", note: "apple", url: "https://github.com/apple/swift-nio"),
		.init(name: "Nuke", note: "kean", url: "https://github.com/kean/Nuke"),
		.init(name: "Zip", note: "marmelroy", url: "https://github.com/marmelroy/Zip"),
		.init(name: "SWCompression", note: "tsolomko", url: "https://github.com/tsolomko/SWCompression"),
		.init(name: "OpenSSL", note: "krzyzanowskim", url: "https://github.com/krzyzanowskim/OpenSSL"),
		.init(name: "Sora · JetBrains Mono", note: String.localized("Fonts, SIL Open Font License"), url: "https://openfontlicense.org"),
	]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				AccretionBackButton()
				_hero()
				_build()
				_group(String.localized("Accretion")) {
					_web(String.localized("Accretion Store"), "getaccretion.app", "storefront", "https://getaccretion.app")
					_divider()
					_web(String.localized("What's New"), String.localized("Every release and its changes"), "sparkles", "https://github.com/GETAccretion/accretion-app/releases")
					_divider()
					_web(String.localized("Source Code"), "GETAccretion/accretion-app", "chevron.left.forwardslash.chevron.right", "https://github.com/GETAccretion/accretion-app")
					_divider()
					_web(String.localized("Accretion Mods"), "AccretionMods/mods", "wand.and.stars", "https://github.com/AccretionMods/mods")
					_divider()
					_web(String.localized("Support Accretion"), "Ko-fi", "heart", "https://ko-fi.com/getaccretion")
					if _consent.privacyOptionsRequired {
						_divider()
						_privacyChoices()
					}
				}
				_feather()
				_credits(String.localized("Made by"), _accretionCredits)
				_credits(String.localized("Feather developers"), _featherCredits, footer: String.localized("Feather's developers made the app Accretion is based on. They aren't involved in Accretion, so please send Accretion questions to Accretion, not to them."))
				_group(String.localized("Open Source")) {
					ForEach(Array(_libraries.enumerated()), id: \.element) { index, library in
						if index > 0 { _divider() }
						_web(library.name, library.note, "shippingbox", library.url)
					}
				}
				Text(verbatim: "Accretion · GPL-3.0")
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
					.frame(maxWidth: .infinity)
					.padding(.top, 4)
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar).accretionStatusBarBackdrop()
	}

	// MARK: Build facts
	private var _buildNumber: String {
		Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
	}

	/// Betas have four numbers (1.0.27.1); they only reach people with Beta Updates on
	private var _isBetaBuild: Bool {
		Bundle.main.version.split(separator: ".").count > 3
	}

	private var _channel: String {
		_betaUpdates ? String.localized("Beta") : String.localized("Stable")
	}

	private var _deviceModel: String {
		var info = utsname()
		uname(&info)
		let machine = withUnsafeBytes(of: &info.machine) { raw in
			String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
		}
		return machine.isEmpty ? UIDevice.current.model : machine
	}

	private var _diagnostics: String {
		[
			"Accretion \(Bundle.main.version) (\(_buildNumber))",
			"Update channel: \(_betaUpdates ? "beta" : "stable")",
			"iOS \(UIDevice.current.systemVersion) · \(_deviceModel)",
		].joined(separator: "\n")
	}

	// MARK: Pieces
	private func _hero() -> some View {
		VStack(spacing: 10) {
			FRAppIconView(size: 84)
			Text(verbatim: Bundle.main.name)
				.font(.accretionDisplay(30, weight: .heavy))
				.foregroundStyle(AccretionTheme.fg)
			Text(verbatim: String.localized("Every source, pulled into one."))
				.font(.subheadline)
				.foregroundStyle(AccretionTheme.muted)
			HStack(spacing: 6) {
				AccretionBadge(text: "v\(Bundle.main.version)", color: AccretionTheme.link)
				if _isBetaBuild {
					AccretionBadge(text: String.localized("Beta"), color: AccretionTheme.warn)
				}
			}
		}
		.frame(maxWidth: .infinity)
		.padding(.vertical, 22)
		.accretionCard()
	}

	private func _build() -> some View {
		AccretionSection(String.localized("This Build")) {
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
				AccretionFact(label: String.localized("Version"), value: Bundle.main.version)
				AccretionFact(label: String.localized("Build"), value: _buildNumber)
				AccretionFact(label: String.localized("Updates"), value: _channel)
				AccretionFact(label: "iOS", value: UIDevice.current.systemVersion)
			}
			AccretionFact(label: String.localized("Device"), value: _deviceModel)
			HStack(spacing: 8) {
				Button {
					UIPasteboard.general.string = _diagnostics
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					_copied = true
				} label: {
					Label(
						_copied ? String.localized("Copied") : String.localized("Copy Details"),
						systemImage: _copied ? "checkmark" : "doc.on.doc"
					)
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false))
				Button {
					UIApplication.open("https://github.com/GETAccretion/accretion-app/issues/new/choose")
				} label: {
					Label(String.localized("Report a Problem"), systemImage: "exclamationmark.bubble")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle(prominent: true))
			}
			Text(verbatim: String.localized("Paste the copied details into your report, so it can be reproduced."))
				.font(.caption)
				.foregroundStyle(AccretionTheme.muted)
		}
	}

	/// Accretion is a Feather fork: the credit and the licence that has to travel with it
	private func _feather() -> some View {
		AccretionSection(String.localized("Built on Feather")) {
			Text(verbatim: String.localized("Accretion is an independent app based on Feather, made by claration, Asami and Feather's contributors. Both are free software under the GNU General Public License v3.0: you can use, study, share and change them, and Accretion's full source code is public."))
				.font(.subheadline)
				.foregroundStyle(AccretionTheme.fg)
				.fixedSize(horizontal: false, vertical: true)
			AccretionFlow(spacing: 8) {
				Button(String.localized("Feather on GitHub")) { UIApplication.open("https://github.com/claration/Feather") }
					.buttonStyle(AccretionButtonStyle(prominent: false))
				Button(String.localized("GPL-3.0 Licence")) { UIApplication.open("https://www.gnu.org/licenses/gpl-3.0.html") }
					.buttonStyle(AccretionButtonStyle(prominent: false))
			}
		}
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

	private func _row<Leading: View>(_ title: String, _ subtitle: String, @ViewBuilder leading: () -> Leading) -> some View {
		HStack(spacing: 12) {
			leading()
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: title).accretionFont(15, weight: .semibold).foregroundStyle(AccretionTheme.fg)
				Text(verbatim: subtitle).font(.caption).foregroundStyle(AccretionTheme.muted).lineLimit(1)
			}
			Spacer(minLength: 0)
			Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(AccretionTheme.muted)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 11)
		.contentShape(Rectangle())
	}

	private func _web(_ title: String, _ subtitle: String, _ icon: String, _ url: String) -> some View {
		Button {
			UIApplication.open(url)
		} label: {
			_row(title, subtitle) {
				Image(systemName: icon)
					.accretionFont(15, weight: .semibold)
					.foregroundStyle(AccretionTheme.accent2)
					.frame(width: 32, height: 32)
					.background(AccretionTheme.accent2.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			}
		}
		.buttonStyle(.plain)
	}

	private func _privacyChoices() -> some View {
		Button {
			AccretionAds.presentPrivacyOptions()
		} label: {
			_row(String.localized("Privacy choices"), String.localized("Ad consent"), leading: {
				Image(systemName: "hand.raised")
					.accretionFont(15, weight: .semibold)
					.foregroundStyle(AccretionTheme.accent2)
					.frame(width: 32, height: 32)
					.background(AccretionTheme.accent2.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
			})
		}
		.buttonStyle(.plain)
	}

	private func _credits(_ title: String, _ credits: [Credit], footer: String? = nil) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			_group(title) {
				ForEach(Array(credits.enumerated()), id: \.element) { index, credit in
					if index > 0 { _divider() }
					_creditRow(credit)
				}
			}
			if let footer {
				Text(verbatim: footer)
					.font(.caption)
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.horizontal, 4)
			}
		}
	}

	private func _creditRow(_ credit: Credit) -> some View {
		Button {
			UIApplication.open("https://github.com/\(credit.github)")
		} label: {
			_row(credit.name, credit.role) {
				AsyncImage(url: URL(string: "https://github.com/\(credit.github).png?size=96")) { image in
					image.resizable().scaledToFill()
				} placeholder: {
					AccretionTheme.raised
				}
				.frame(width: 32, height: 32)
				.clipShape(Circle())
				.overlay(Circle().stroke(AccretionTheme.line, lineWidth: 1))
			}
		}
		.buttonStyle(.plain)
	}
}
