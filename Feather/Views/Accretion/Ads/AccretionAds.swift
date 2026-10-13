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

@MainActor
enum AccretionAds {
	/// AdMob "Download card" banner unit (the app ID is `GADApplicationIdentifier` in Info.plist).
	/// For testing, Google's test unit is ca-app-pub-3940256099942544/2435281174.
	static let bannerUnitID = "ca-app-pub-4500603236648893/7187717610"

	private static var _started = false

	/// Starts the ads SDK once. No tracking prompt is requested.
	static func start() {
		guard !_started else { return }
		_started = true
		MobileAds.shared.start(completionHandler: nil)
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
/// account is ad-free or the ad fails to load.
struct AccretionAdCard: View {
	@ObservedObject private var _eligibility = AdEligibility.shared
	@State private var _failed = false

	var body: some View {
		if _eligibility.showAds && !_failed {
			VStack(alignment: .leading, spacing: 6) {
				AccretionBadge(text: "Ad", color: AccretionTheme.muted)
				_AdBanner(width: Self._bannerWidth) { _failed = true }
					.frame(maxWidth: .infinity)
			}
			.padding(10)
			.accretionCard()
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
		banner.rootViewController = Self._rootViewController
		banner.delegate = context.coordinator
		banner.load(Request())
		return banner
	}

	func updateUIView(_ banner: BannerView, context: Context) {
		if banner.rootViewController == nil { banner.rootViewController = Self._rootViewController }
	}

	func sizeThatFits(_ proposal: ProposedViewSize, uiView banner: BannerView, context: Context) -> CGSize? {
		banner.adSize.size
	}

	private static var _rootViewController: UIViewController? {
		UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first(where: \.isKeyWindow)?
			.rootViewController
	}

	final class Coordinator: NSObject, BannerViewDelegate {
		let onFail: () -> Void
		init(onFail: @escaping () -> Void) { self.onFail = onFail }

		func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
			onFail()
		}
	}
}
