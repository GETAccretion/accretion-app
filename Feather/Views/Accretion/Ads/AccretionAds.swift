//
//  AccretionAds.swift
//  Accretion
//
//  Banner ad card shown under the download progress. Hidden for admins and supporters.
//

import Combine
import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

@MainActor
enum AccretionAds {
	/// AdMob "Download card" banner unit (the app ID is `GADApplicationIdentifier` in Info.plist).
	/// For testing, Google's test unit is ca-app-pub-3940256099942544/2435281174.
	static let bannerUnitID = "ca-app-pub-1352971207491342/9083443164"

	private static var _started = false
	private static var _consentStarted = false

	/// Asks for ad consent (Google's User Messaging Platform: the GDPR message for EU/UK users),
	/// then starts the ads SDK, only if consent allows ads. Never blocks launch: everything is
	/// asynchronous, and the ad card shows the sponsor card until ads are allowed. No tracking
	/// prompt (ATT) is requested.
	static func start() {
		guard !_consentStarted else { return }
		_consentStarted = true
		// A previous launch may already have gathered consent: start right away, as Google recommends
		AdConsent.shared.refresh()
		if AdConsent.shared.canRequestAds { _startAds() }
		ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { _ in
			Task { @MainActor in
				// At launch the window may not be key yet: wait for it (up to ~5 s) so the form can show
				for _ in 0..<20 where rootViewController == nil {
					try? await Task.sleep(nanoseconds: 250_000_000)
				}
				// Shows the form only when the user's region requires it. On any error, canRequestAds
				// still reflects the last known consent state.
				ConsentForm.loadAndPresentIfRequired(from: rootViewController) { _ in
					Task { @MainActor in
						AdConsent.shared.refresh()
						if AdConsent.shared.canRequestAds { _startAds() }
					}
				}
			}
		}
	}

	/// Shows the "Privacy choices" form so the user can change their ad consent
	static func presentPrivacyOptions() {
		ConsentForm.presentPrivacyOptionsForm(from: rootViewController) { _ in
			Task { @MainActor in
				AdConsent.shared.refresh()
				if AdConsent.shared.canRequestAds { _startAds() }
			}
		}
	}

	private static func _startAds() {
		guard !_started else { return }
		_started = true
		MobileAds.shared.start(completionHandler: nil)
	}

	static var rootViewController: UIViewController? {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first(where: \.isKeyWindow)?
			.rootViewController
	}
}

/// Mirrors Google's consent state for the UI: whether ads may be requested, and whether the
/// "Privacy choices" entry must be offered.
@MainActor
final class AdConsent: ObservableObject {
	static let shared = AdConsent()

	@Published private(set) var canRequestAds: Bool
	@Published private(set) var privacyOptionsRequired: Bool

	private init() {
		canRequestAds = ConsentInformation.shared.canRequestAds
		privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
	}

	func refresh() {
		canRequestAds = ConsentInformation.shared.canRequestAds
		privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
	}
}

/// Whether this account sees ads. Stays false until the check finishes (so an admin never sees a
/// flash of an ad); the last answer is cached so it is instant next launch.
@MainActor
final class AdEligibility: ObservableObject {
	static let shared = AdEligibility()

	@Published private(set) var showAds: Bool
	private static let _cacheKey = "Accretion.showAds"
	private var _bag = Set<AnyCancellable>()

	private init() {
		showAds = UserDefaults.standard.bool(forKey: Self._cacheKey)
		// The sink runs before `email` changes; the Task hops so refresh() sees the new value.
		AccretionAccount.shared.$email
			.sink { [weak self] _ in Task { await self?._refresh() } }
			.store(in: &_bag)
	}

	private func _refresh() async {
		// Signed out: ads show. Signed in: hidden for admins and supporters. If the check fails
		// (offline), keep the last answer rather than show an admin an ad.
		guard let adFree = await AccretionAccount.shared.adFree() else { return }
		let show = !adFree
		showAds = show
		UserDefaults.standard.set(show, forKey: Self._cacheKey)
	}
}

/// Store-style card with a small "Ad" label and an adaptive banner. Renders nothing when the
/// account is ad-free; when AdMob has no ad, shows Accretion's own sponsor card instead.
/// `googleAd` is false while another source's app downloads: those get the sponsor card, so
/// Google's ads only ever run next to Accretion's own builds (the website follows the same rule).
struct AccretionAdCard: View {
	var googleAd = true
	@ObservedObject private var _eligibility = AdEligibility.shared
	@ObservedObject private var _consent = AdConsent.shared
	@State private var _failed = false

	var body: some View {
		if _eligibility.showAds {
			if !googleAd || _failed || !_consent.canRequestAds {
				// No ad consent yet, or AdMob had no ad (common while serving is limited): our own sponsor card (no tracking) instead
				AccretionSponsorCard()
			} else {
				VStack(alignment: .leading, spacing: 6) {
					AccretionBadge(text: "Ad", color: AccretionTheme.muted)
					_AdBanner(width: Self._bannerWidth) { _failed = true }
						.frame(maxWidth: .infinity)
				}
				.padding(10)
				.accretionCard()
			}
		}
	}

	/// Screen width less the list margin (16 each side) and the card padding (10 each side)
	private static var _bannerWidth: CGFloat {
		let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
		return floor((screen?.bounds.width ?? 375) - 52)
	}
}

private struct _AdBanner: UIViewRepresentable {
	let width: CGFloat
	let onFail: () -> Void

	func makeCoordinator() -> Coordinator { Coordinator(onFail: onFail) }

	func makeUIView(context: Context) -> BannerView {
		let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
		banner.adUnitID = AccretionAds.bannerUnitID
		banner.rootViewController = AccretionAds.rootViewController
		banner.delegate = context.coordinator
		banner.load(Request())
		return banner
	}

	func updateUIView(_ banner: BannerView, context: Context) {
		if banner.rootViewController == nil { banner.rootViewController = AccretionAds.rootViewController }
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView banner: BannerView, context: Context) -> CGSize? {
		banner.adSize.size
	}

	final class Coordinator: NSObject, BannerViewDelegate {
		let onFail: () -> Void
		init(onFail: @escaping () -> Void) { self.onFail = onFail }

		func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
			onFail()
		}
	}
}

// MARK: - Sponsor fallback
/// One offer from the store's support.json (edited on the website repo, no app update needed):
/// "sponsors" first, then the signing-certificate offers, then the Ko-fi link.
struct SponsorOffer: Decodable, Hashable {
	let name: String
	let text: String
	let url: URL
	let icon: String
	let isOwn: Bool

	private enum CodingKeys: String, CodingKey { case name, text, note, url }

	init(name: String, text: String, url: URL, icon: String, isOwn: Bool) {
		self.name = name
		self.text = text
		self.url = url
		self.icon = icon
		self.isOwn = isOwn
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		name = try c.decode(String.self, forKey: .name)
		text = (try? c.decode(String.self, forKey: .text)) ?? (try? c.decode(String.self, forKey: .note)) ?? ""
		url = try c.decode(URL.self, forKey: .url)
		icon = "star.circle"
		isOwn = false
	}
}

/// Loads support.json once per launch and picks an offer for each card
@MainActor
final class SponsorStore: ObservableObject {
	static let shared = SponsorStore()

	@Published private(set) var offers: [SponsorOffer] = []
	private var _loaded = false

	private struct Support: Decodable {
		let kofi: String?
		let sponsors: [SponsorOffer]?
		let certificates: [SponsorOffer]?
	}

	func load() async {
		guard !_loaded else { return }
		_loaded = true
		let url = StoreService.base.appendingPathComponent("support.json")
		guard
			let (data, _) = try? await URLSession.shared.data(from: url),
			let support = try? JSONDecoder().decode(Support.self, from: data)
		else { return }
		let paid = (support.sponsors ?? []) + (support.certificates ?? []).map {
			SponsorOffer(name: $0.name, text: $0.text.isEmpty ? String.localized("Signing certificate") : $0.text, url: $0.url, icon: "checkmark.seal", isOwn: false)
		}
		if !paid.isEmpty {
			offers = paid.filter { $0.url.scheme == "https" }
		} else if let kofi = support.kofi.flatMap(URL.init(string:)), kofi.scheme == "https" {
			offers = [SponsorOffer(
				name: String.localized("Support Accretion"),
				text: String.localized("Accretion is free. A coffee on Ko-fi keeps it running."),
				url: kofi, icon: "heart.fill", isOwn: true
			)]
		}
	}
}

/// The sponsor card: same place and size class as the ad, labelled "Sponsored" (or "Accretion" for
/// our own Ko-fi link). Renders nothing until an offer has loaded.
struct AccretionSponsorCard: View {
	@ObservedObject private var _store = SponsorStore.shared
	@State private var _pick: SponsorOffer?

	var body: some View {
		Group {
			if let offer = _pick {
				Button {
					UIApplication.shared.open(offer.url)
				} label: {
					HStack(spacing: 12) {
						Image(systemName: offer.icon)
							.accretionFont(17, weight: .semibold)
							.foregroundStyle(offer.isOwn ? AccretionTheme.accent : AccretionTheme.accent2)
							.frame(width: 38, height: 38)
							.background((offer.isOwn ? AccretionTheme.accent : AccretionTheme.accent2).opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
						VStack(alignment: .leading, spacing: 3) {
							HStack(spacing: 6) {
								Text(verbatim: offer.name).accretionFont(15, weight: .semibold).foregroundStyle(AccretionTheme.fg).lineLimit(1)
								AccretionBadge(text: offer.isOwn ? "Accretion" : String.localized("Sponsored"), color: AccretionTheme.muted)
							}
							Text(verbatim: offer.text).font(.caption).foregroundStyle(AccretionTheme.muted).lineLimit(2)
						}
						Spacer(minLength: 0)
						Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(AccretionTheme.muted)
					}
					.padding(12)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accretionCard()
			}
		}
		.task {
			await _store.load()
			if _pick == nil { _pick = _store.offers.randomElement() }
		}
		.onChange(of: _store.offers) { offers in
			if _pick == nil { _pick = offers.randomElement() }
		}
	}
}
