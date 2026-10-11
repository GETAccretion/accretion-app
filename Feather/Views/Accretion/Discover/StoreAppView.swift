//
//  StoreAppView.swift
//  Accretion
//

import SwiftUI
import NukeUI

// MARK: - App page
/// An app's page in Discover, laid out like the web store's: header, Install, facts,
/// what's new, screenshots, about and versions.
struct StoreAppView: View {
	@ObservedObject private var _store = StoreService.shared
	@ObservedObject private var _pipeline = AutoSignPipeline.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@State private var _isSigningIn = false
	let app: StoreApp
	@State private var _detail: StoreAppDetail?

	private var _latest: StoreAppDetail.Version? { _detail?.versions.first }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				HStack(alignment: .top, spacing: 14) {
					StoreAppIcon(url: app.iconURL, size: 96)
					VStack(alignment: .leading, spacing: 6) {
						Text(verbatim: app.n)
							.font(.accretionDisplay(24))
							.foregroundStyle(AccretionTheme.fg)
						Text(verbatim: app.d)
							.foregroundStyle(AccretionTheme.muted)
						HStack(spacing: 6) {
							if _store.isMod(app) { AccretionBadge(text: "Accretion Mod", color: AccretionTheme.accent) }
							if _store.isNew(app) { AccretionBadge(text: "new") }
							if !_store.fits(app) { AccretionBadge(text: "needs iOS \(app.m ?? "")", color: AccretionTheme.warn) }
						}
					}
				}

				HStack(spacing: 10) {
					Button {
						// downloads need an Accretion account, like on the web store
						guard _account.isSignedIn else { _isSigningIn = true; return }
						if let url = _latest.flatMap({ URL(string: $0.url) }) {
							_pipeline.install(name: app.n, bundleID: app.i, downloadURL: url)
						}
					} label: {
						Label(String.localized("Install"), systemImage: "arrow.down.circle.fill")
					}
					.buttonStyle(AccretionButtonStyle())
					.disabled(_latest == nil || _pipeline.isRunning)

					if let url = _latest.flatMap({ URL(string: $0.url) }) {
						Button {
							guard _account.isSignedIn else { _isSigningIn = true; return }
							LiveContainer.install(from: url)
						} label: {
							Label(String.localized("LiveContainer"), systemImage: "shippingbox")
						}
						.buttonStyle(AccretionButtonStyle(prominent: false))
					}
				}
				if let status = _pipeline.status {
					Text(verbatim: status).font(.footnote).foregroundStyle(AccretionTheme.muted)
				}

				_facts()

				if let notes = _latest?.notes, !notes.isEmpty {
					_section(String.localized("What's new")) { Text(verbatim: notes).foregroundStyle(AccretionTheme.fg) }
				}
				if let shots = _detail?.shots, !shots.isEmpty {
					_section(String.localized("Screenshots")) {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								ForEach(shots, id: \.self) { shot in
									LazyImage(url: URL(string: shot)) { state in
										if let image = state.image { image.resizable().scaledToFit() } else { AccretionTheme.raised }
									}
									.frame(height: 380)
									.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
								}
							}
						}
					}
				}
				if let desc = _detail?.desc, !desc.isEmpty {
					_section(String.localized("About")) { Text(verbatim: desc).foregroundStyle(AccretionTheme.fg) }
				}
				_section(String.localized("Info")) {
					VStack(alignment: .leading, spacing: 6) {
						_fact(String.localized("Bundle ID"), app.i)
						_fact(String.localized("Listed by"), _store.source(of: app)?.name ?? "–")
						Text(verbatim: _store.isMod(app)
							? String.localized("Built by Accretion from a free or open-source app.")
							: String.localized("Files are hosted by the source above, not by Accretion. Install what you trust."))
							.font(.footnote)
							.foregroundStyle(AccretionTheme.muted)
					}
				}
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationBarTitleDisplayMode(.inline)
		.task { _detail = await _store.detail(for: app) }
		.sheet(isPresented: $_isSigningIn) {
			NavigationStack { AccretionAccountView() }
		}
	}

	private func _facts() -> some View {
		HStack(spacing: 10) {
			_factCard(String.localized("Version"), app.v)
			_factCard(String.localized("Updated"), StoreFormat.since(app))
			_factCard(String.localized("Size"), app.z.map(StoreFormat.bytes) ?? "–")
			_factCard(String.localized("Min iOS"), app.m ?? "–")
		}
	}

	private func _factCard(_ label: String, _ value: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: label.uppercased()).font(.accretionMono(9)).foregroundStyle(AccretionTheme.muted)
			Text(verbatim: value).font(.system(size: 13, weight: .semibold)).foregroundStyle(AccretionTheme.fg).lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(10)
		.accretionCard()
	}

	private func _fact(_ label: String, _ value: String) -> some View {
		HStack {
			Text(verbatim: label).foregroundStyle(AccretionTheme.muted)
			Spacer()
			Text(verbatim: value).foregroundStyle(AccretionTheme.fg).lineLimit(1)
		}
		.font(.subheadline)
	}

	private func _section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(verbatim: title).font(.accretionDisplay(18)).foregroundStyle(AccretionTheme.fg)
			content()
		}
	}
}
