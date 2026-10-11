//
//  StoreAppView.swift
//  Accretion
//

import SwiftUI
import UIKit
import NukeUI

// MARK: - App page
/// An app's page in Discover, a copy of the web store's app page (site/app.js `openApp`):
/// back, header card with the install buttons, likes and ratings, facts, what's new,
/// screenshots, about, versions, permissions, related shelves, info and comments.
struct StoreAppView: View {
	@ObservedObject private var _store = StoreService.shared
	@ObservedObject private var _pipeline = AutoSignPipeline.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@Environment(\.openURL) private var _openURL
	let app: StoreApp

	@State private var _detail: StoreAppDetail?
	@State private var _detailLoaded = false
	@State private var _isSigningIn = false
	@State private var _social: AccretionAccount.AppSocial?
	@State private var _socialError: String?
	@State private var _posts: [AccretionAccount.Post]?
	@State private var _draft = ""
	@State private var _replyTo: AccretionAccount.Post?
	@State private var _isPosting = false
	@State private var _isLiking = false
	/// Worked out once per page, not on every redraw (typing a comment redraws the page)
	@State private var _sameDeveloper: [StoreApp] = []
	@State private var _similar: [StoreApp] = []
	@State private var _replies: [Int: [AccretionAccount.Post]] = [:]
	@State private var _threadError: String?
	@State private var _toast: String?
	/// The installer the Install button uses, remembered like the website's choice
	@AppStorage("accretion.installer") private var _installerID = "accretion"
	@State private var _isChoosingInstaller = false

	private var _latest: StoreAppDetail.Version? { _detail?.versions.first }
	private var _ipa: URL? { _latest.flatMap { URL(string: $0.url) } }
	private var _tint: Color {
		guard let hex = _detail?.tint, hex.count == 6, let value = UInt32(hex, radix: 16) else { return AccretionTheme.accent }
		return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				AccretionBackButton()
					.padding(.bottom, 2)
				_head()
				_community()
				if _detail != nil {
					_body()
				} else if _detailLoaded {
					Text(verbatim: String.localized("Details couldn't load. Check your connection and refresh."))
						.foregroundStyle(AccretionTheme.muted)
				}
				_comments()
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar)
		.overlay(alignment: .bottom) { _toastView() }
		.task {
			_account.track("view", app: app.i)
			_store.markSeen(app)
			let others = _store.index?.apps ?? []
			_sameDeveloper = Array(others.filter { $0.d == app.d && $0.i != app.i }.sorted { $0.t > $1.t }.prefix(20))
			_similar = Array(others.filter { $0.c == app.c && $0.i != app.i && $0.d != app.d && $0.c != "other" }.sorted { $0.t > $1.t }.prefix(20))
			_detail = await _store.detail(for: app)
			_detailLoaded = true
		}
		.task(id: _account.email) { await _loadCommunity() }
		.sheet(isPresented: $_isSigningIn) {
			NavigationStack { AccretionAccountView() }
		}
	}

	// MARK: Header (.d-head)
	private func _head() -> some View {
		HStack(alignment: .center, spacing: 14) {
			StoreAppIcon(url: app.iconURL, size: 80)
			VStack(alignment: .leading, spacing: 0) {
				Text(verbatim: app.n)
					.font(.accretionDisplay(24))
					.foregroundStyle(AccretionTheme.fg)
					.fixedSize(horizontal: false, vertical: true)
				NavigationLink(value: StoreListRoute(title: app.d, developer: app.d)) {
					Text(verbatim: app.d).underline().foregroundStyle(AccretionTheme.muted)
				}
				.buttonStyle(.plain)
				.padding(.top, 4)
				if let subtitle = app.s, !subtitle.isEmpty {
					Text(verbatim: subtitle)
						.foregroundStyle(AccretionTheme.fg)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.top, 8)
				}
				if !_store.fits(app) {
					Text(verbatim: String.localized("Needs iOS %@ or later. This device is on %@.", arguments: app.m ?? "", UIDevice.current.systemVersion))
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(AccretionTheme.warn)
						.padding(.top, 10)
				}
				if _detail != nil {
					_actions().padding(.top, 16)
					if let status = _pipeline.status, _pipeline.activeBundleID == app.i {
						Text(verbatim: status).font(.footnote).foregroundStyle(AccretionTheme.muted).padding(.top, 8)
					}
					if _ipa != nil {
						Button { _openURL(URL(string: "https://getaccretion.github.io/#/sign")!) } label: {
							Text(verbatim: String.localized("How to sign your own apps →")).underline()
						}
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.accent2)
						.padding(.top, 10)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(16)
		.background {
			ZStack {
				AccretionTheme.surface
				GeometryReader { geo in
					RadialGradient(colors: [_tint.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.45)
						.frame(width: geo.size.width * 0.9, height: geo.size.height * 1.4)
						.offset(x: geo.size.width * 0.35, y: -geo.size.height * 0.3)
				}
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}

	/// Install, Download IPA, the other installers, Save, Share, Copy IPA link
	private func _actions() -> some View {
		AccretionFlow(spacing: 8) {
			if let ipa = _ipa {
				let installer = _Installer.all.first { $0.id == _installerID } ?? _Installer.all[0]
				Button(installer.id == "accretion" ? String.localized("Install") : String.localized("Install with %@", arguments: installer.name)) {
					guard _needsAccount() else { return }
					_install(ipa, with: installer)
				}
				.buttonStyle(AccretionButtonStyle())
				.disabled(installer.id == "accretion" && _pipeline.isRunning)

				Button(String.localized("Change")) { _isChoosingInstaller = true }
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
					.confirmationDialog(String.localized("Install button uses…"), isPresented: $_isChoosingInstaller, titleVisibility: .visible) {
						ForEach(_Installer.all) { option in
							Button(option.name + (option.id == _installerID ? " ✓" : "")) {
								_installerID = option.id
								_show(String.localized("Install uses %@", arguments: option.name))
							}
						}
					} message: {
						Text(verbatim: String.localized("Accretion signs and installs here with your certificate. The others open the app in that installer."))
					}

				Button(String.localized("Download IPA")) {
					guard _needsAccount() else { return }
					Task {
						_ = DownloadManager.shared.startDownload(from: await _resolved(ipa))
						_show(String.localized("Downloading to your Library"))
					}
				}
				.buttonStyle(AccretionButtonStyle(prominent: false))

			}

			Button(_store.isSaved(app) ? String.localized("Saved") : String.localized("Save")) {
				_store.toggleSaved(app)
				_show(_store.isSaved(app) ? String.localized("Saved. You'll see when it updates.") : String.localized("Removed from saved"))
			}
			.buttonStyle(AccretionButtonStyle(prominent: false, on: _store.isSaved(app)))

			ShareLink(item: StoreService.base.appendingPathComponent("app/\(app.i)/")) {
				Text(verbatim: String.localized("Share"))
			}
			.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))

			if let ipa = _ipa {
				Button(String.localized("Copy IPA link")) {
					guard _needsAccount() else { return }
					Task {
						UIPasteboard.general.string = await _resolved(ipa).absoluteString
						_show(String.localized("IPA link copied"))
					}
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true))
			}
		}
	}

	/// The web store's installers (AltStore and friends), opened with the app's download link.
	private struct _Installer: Identifiable {
		let id: String
		let name: String
		let link: (URL) -> URL?

		static let all: [_Installer] = [
			_Installer(id: "accretion", name: "Accretion") { _ in nil },
			_Installer(id: "livecontainer", name: "LiveContainer") { _ in nil },
			_Installer(id: "feather", name: "Feather") { URL(string: "feather://install/\($0.absoluteString)") },
			_Installer(id: "altstore", name: "AltStore") { _Installer._query("altstore://install", $0) },
			_Installer(id: "sidestore", name: "SideStore") { _Installer._query("sidestore://install", $0) },
			_Installer(id: "trollstore", name: "TrollStore") { _Installer._query("apple-magnifier://install", $0) },
		]

		private static func _query(_ base: String, _ url: URL) -> URL? {
			var components = URLComponents(string: base)
			components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
			return components?.url
		}
	}

	private func _install(_ ipa: URL, with installer: _Installer) {
		_account.track("install", app: app.i)
		switch installer.id {
		case "accretion":
			_pipeline.install(name: app.n, bundleID: app.i, downloadURL: ipa)
		default:
			Task {
				let url = await _resolved(ipa)
				if installer.id == "livecontainer" { LiveContainer.install(from: url) } else if let link = installer.link(url) { _openURL(link) }
			}
		}
	}

	// MARK: Likes and ratings (.community-top)
	@ViewBuilder
	private func _community() -> some View {
		AccretionSection(nil) {
			if let social = _social {
				AccretionFlow(spacing: 12) {
					Button {
						guard _needsAccount(), !_isLiking else { return }
						_isLiking = true
						Task {
							defer { _isLiking = false }
							do {
								let liked = !(_social?.liked ?? false)
								try await _account.likeApp(app.i, liked)
								_social?.liked = liked
								_social?.likes += liked ? 1 : -1
							} catch { _show(error.localizedDescription) }
						}
					} label: {
						Text(verbatim: "♥ " + (social.liked ? String.localized("Liked") : String.localized("Like")) + (social.likes > 0 ? " · \(social.likes)" : ""))
					}
					.buttonStyle(AccretionButtonStyle(prominent: false, on: social.liked))

					HStack(spacing: 10) {
						HStack(spacing: 2) {
							ForEach(1...5, id: \.self) { star in
								Button {
									guard _needsAccount() else { return }
									Task {
										do {
											try await _account.rateApp(app.i, stars: star)
											_applyRating(star)
											_show(String.localized("Thanks for rating"))
										} catch { _show(error.localizedDescription) }
									}
								} label: {
									Text(verbatim: "★")
										.font(.system(size: 24))
										.foregroundStyle(star <= social.stars ? AccretionTheme.star : AccretionTheme.line)
										.padding(2)
								}
								.buttonStyle(.plain)
								.accessibilityLabel(String.localized("%@ stars", arguments: String(star)))
							}
						}
						Text(verbatim: social.average.map {
							String.localized("%@ ★ from %@ ratings", arguments: String(format: "%.1f", $0), String(social.ratings))
						} ?? String.localized("No ratings yet"))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
					}
				}
			} else {
				Text(verbatim: _socialError ?? String.localized("Loading community…"))
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
			}
		}
	}

	// MARK: Details
	@ViewBuilder
	private func _body() -> some View {
		let latest = _latest
		_factsGrid([
			(String.localized("Version"), latest?.v ?? ""),
			(String.localized("Build"), latest?.b ?? ""),
			(String.localized("Released"), app.u != nil
				? String.localized("Unknown (the source gives no date)")
				: latest.map { "\($0.t) · \(StoreFormat.ago($0.t))" } ?? ""),
			(String.localized("Size"), latest?.z.map(StoreFormat.bytes) ?? ""),
			(String.localized("Min iOS"), latest?.min ?? ""),
			(String.localized("Category"), StoreService.categoryNames[app.c] ?? app.c),
		])
		.padding(.vertical, 4)

		if let notes = latest?.notes, !notes.isEmpty {
			AccretionSection(String.localized("What's new")) { _prose(notes) }
		}
		if let shots = _detail?.shots, !shots.isEmpty {
			AccretionSection(String.localized("Screenshots")) {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 10) {
						ForEach(shots, id: \.self) { shot in
							LazyImage(url: URL(string: shot)) { state in
								if let image = state.image { image.resizable().scaledToFit() } else { AccretionTheme.raised.frame(width: 166) }
							}
							.frame(height: 300)
							.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
							.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
						}
					}
				}
			}
		}
		if let desc = _detail?.desc, !desc.isEmpty {
			AccretionSection(String.localized("About")) { _prose(desc) }
		}
		if let versions = _detail?.versions, !versions.isEmpty {
			AccretionSection(String.localized("Versions")) {
				VStack(spacing: 8) {
					ForEach(Array(versions.enumerated()), id: \.offset) { index, version in
						_versionRow(version, isLatest: index == 0)
					}
				}
			}
		}
		if let perms = _detail?.perms, !(perms.privacy.isEmpty && perms.entitlements.isEmpty) {
			AccretionSection(String.localized("Permissions")) {
				AccretionFlow(spacing: 6) {
					ForEach(perms.privacy.map(_privacyName) + perms.entitlements, id: \.self) { name in
						Text(verbatim: name)
							.font(.accretionMono(12, weight: .regular))
							.foregroundStyle(AccretionTheme.fg)
							.padding(.horizontal, 8)
							.padding(.vertical, 4)
							.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
					}
				}
			}
		}

		let sameDeveloper = _sameDeveloper
		let similar = _similar
		if !sameDeveloper.isEmpty {
			StoreShelfView(shelf: .init(id: "dev", title: String.localized("More from %@", arguments: app.d), note: nil, apps: Array(sameDeveloper.prefix(20))))
				.padding(.top, 8)
		}
		if !similar.isEmpty {
			StoreShelfView(shelf: .init(
				id: "similar",
				title: String.localized("More %@", arguments: StoreService.categoryNames[app.c] ?? ""),
				note: String.localized("recently updated"),
				apps: Array(similar.prefix(20)),
				seeAll: StoreListRoute(title: StoreService.categoryNames[app.c] ?? app.c, category: app.c)
			))
		}

		AccretionSection(String.localized("Info")) {
			_factsGrid([
				(String.localized("Bundle ID"), app.i),
				(String.localized("Listed by"), _store.source(of: app)?.name ?? "–"),
				(String.localized("First seen"), app.f ?? ""),
			])
			if _store.isMod(app) {
				(Text(verbatim: "ACCRETION MOD").font(.accretionMono(10)).foregroundColor(AccretionTheme.accent)
				 + Text(verbatim: "  ")
				 + Text(_modNote))
				.font(.system(size: 13))
				.foregroundStyle(AccretionTheme.muted)
				.tint(AccretionTheme.accent2)
			} else {
				Text(verbatim: String.localized("Files are hosted by the source above, not by Accretion. Install what you trust."))
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
			}
		}
	}

	private var _modNote: AttributedString {
		let text = String.localized("Built by Accretion from a free or open-source app. Unsigned: sign it with your own tool. Source and build scripts: [AccretionMods/mods](https://github.com/AccretionMods/mods).")
		return (try? AttributedString(markdown: text)) ?? AttributedString(text)
	}

	/// NSCameraUsageDescription → Camera, like the web store
	private func _privacyName(_ key: String) -> String {
		var name = key
		if name.hasPrefix("NS") { name.removeFirst(2) }
		if name.hasSuffix("UsageDescription") { name.removeLast("UsageDescription".count) }
		return name
	}

	/// The store's `.facts` grid: two equal columns on a phone, rows as tall as their tallest cell
	private func _factsGrid(_ facts: [(String, String)]) -> some View {
		Grid(horizontalSpacing: 10, verticalSpacing: 10) {
			ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { start in
				GridRow {
					ForEach(start..<min(start + 2, facts.count), id: \.self) { index in
						AccretionFact(label: facts[index].0, value: facts[index].1)
							.frame(maxHeight: .infinity, alignment: .topLeading)
					}
					if start + 1 >= facts.count { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
				}
			}
		}
	}

	private func _prose(_ text: String) -> some View {
		Text(verbatim: text)
			.foregroundStyle(AccretionTheme.fg)
			.fixedSize(horizontal: false, vertical: true)
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	private func _versionRow(_ version: StoreAppDetail.Version, isLatest: Bool) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			AccretionFlow(spacing: 14) {
				Text(verbatim: "v\(version.v)" + (version.b.map { $0 != version.v ? " (\($0))" : "" } ?? ""))
					.foregroundStyle(AccretionTheme.fg)
				Text(verbatim: "\(version.t) · \(version.z.map(StoreFormat.bytes) ?? "–")" + (version.min.map { " · iOS \($0)+" } ?? ""))
					.foregroundStyle(AccretionTheme.muted)
				if let url = URL(string: version.url) {
					Button {
						guard _needsAccount() else { return }
						Task {
							let link = isLatest ? await _resolved(url) : url
							_ = DownloadManager.shared.startDownload(from: link)
							_show(String.localized("Downloading to your Library"))
						}
					} label: {
						Text(verbatim: String.localized("Download")).underline()
					}
					.buttonStyle(.plain)
					.foregroundStyle(AccretionTheme.accent2)
				}
			}
			.font(.accretionMono(13, weight: .regular))
			if let notes = version.notes, !notes.isEmpty, !isLatest {
				Text(verbatim: notes)
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 10)
		.padding(.horizontal, 12)
		.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
	}

	// MARK: Comments
	private func _comments() -> some View {
		AccretionSection(String.localized("Comments") + ((_social?.comments ?? 0) > 0 ? " · \(_social?.comments ?? 0)" : "")) {
			if _account.isSignedIn {
				_composer()
			} else {
				AccretionFlow(spacing: 10) {
					Text(verbatim: String.localized("Join the conversation."))
						.foregroundStyle(AccretionTheme.fg)
					Button(String.localized("Sign in or create an account")) { _isSigningIn = true }
						.buttonStyle(AccretionButtonStyle())
				}
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
				.padding(.top, 2)
				.padding(.bottom, 6)
			}

			if let error = _threadError {
				Text(verbatim: error)
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.warn)
					.padding(.vertical, 12)
					.padding(.horizontal, 4)
			} else if let posts = _posts {
				let top = posts.filter { $0.parent_id == nil }.reversed()
				if top.isEmpty {
					Text(verbatim: String.localized("No comments yet. Be the first."))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
						.padding(.vertical, 12)
						.padding(.horizontal, 4)
				} else {
					ForEach(Array(top)) { post in
						_post(post)
						ForEach(_replies[post.id] ?? []) { reply in
							_post(reply).padding(.leading, 48)
						}
					}
				}
			}
		}
	}

	private func _composer() -> some View {
		HStack(alignment: .top, spacing: 12) {
			_avatar(name: _account.email ?? "?", color: nil)
			VStack(alignment: .leading, spacing: 8) {
				if let reply = _replyTo {
					HStack {
						Text(verbatim: String.localized("Replying to @%@", arguments: reply.username))
							.font(.system(size: 13))
							.foregroundStyle(AccretionTheme.muted)
						Spacer()
						Button(String.localized("Cancel")) { _replyTo = nil }
							.font(.system(size: 13))
							.foregroundStyle(AccretionTheme.accent2)
					}
				}
				TextField(String.localized("Say something about %@…", arguments: app.n), text: $_draft, axis: .vertical)
					.lineLimit(2...6)
					.foregroundStyle(AccretionTheme.fg)
				HStack {
					Text(verbatim: "\(_draft.count)/2000")
						.font(.accretionMono(11, weight: .regular))
						.foregroundStyle(AccretionTheme.muted)
					Spacer()
					Button(String.localized("Post")) { _submit() }
						.buttonStyle(AccretionButtonStyle(compact: true))
						.disabled(_isPosting || _draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || _draft.count > 2000)
				}
			}
		}
		.padding(12)
		.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
		.padding(.top, 2)
		.padding(.bottom, 6)
	}

	private func _post(_ post: AccretionAccount.Post) -> some View {
		HStack(alignment: .top, spacing: 12) {
			_avatar(name: post.display_name ?? post.username, color: post.color)
			VStack(alignment: .leading, spacing: 4) {
				AccretionFlow(spacing: 6) {
					Text(verbatim: post.display_name?.isEmpty == false ? post.display_name! : post.username)
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(AccretionTheme.fg)
					Text(verbatim: "@\(post.username)")
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
					if let role = post.role, role == "admin" || role == "mod" {
						AccretionBadge(text: role, color: role == "admin" ? Color(red: 244.0 / 255, green: 63.0 / 255, blue: 94.0 / 255) : AccretionTheme.good)
					}
					Text(verbatim: "· " + StoreFormat.ago(post.created_at))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
				}
				Text(verbatim: post.body)
					.foregroundStyle(AccretionTheme.fg)
					.fixedSize(horizontal: false, vertical: true)
				if post.parent_id == nil {
					Button(String.localized("Reply")) {
						guard _needsAccount() else { return }
						_replyTo = post
					}
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(.vertical, 12)
		.padding(.horizontal, 4)
	}

	private func _avatar(name: String, color: String?) -> some View {
		let hex = color.flatMap { UInt32($0, radix: 16) } ?? 0x8B5CF6
		let fill = Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
		return Text(verbatim: String(name.prefix(1)).uppercased())
			.font(.accretionDisplay(15))
			.foregroundStyle(Color.white)
			.frame(width: 36, height: 36)
			.background(fill, in: Circle())
	}

	// MARK: Actions
	private func _loadCommunity() async {
		do {
			_social = try await _account.appSocial(app.i)
			_socialError = nil
		} catch {
			_socialError = error.localizedDescription
		}
		await _loadThread()
	}

	private func _loadThread() async {
		do {
			let posts = try await _account.thread(app.i)
			_replies = Dictionary(grouping: posts.filter { $0.parent_id != nil }) { $0.parent_id ?? 0 }
			_posts = posts
			_threadError = nil
		} catch {
			_threadError = String.localized("Couldn't load comments: %@", arguments: error.localizedDescription)
		}
	}

	/// Keeps "4.3 ★ from 12 ratings" right after rating, without asking the server again
	private func _applyRating(_ star: Int) {
		guard var social = _social else { return }
		let total = (social.average ?? 0) * Double(social.ratings)
		if social.stars == 0 {
			social.ratings += 1
			social.average = (total + Double(star)) / Double(social.ratings)
		} else if social.ratings > 0 {
			social.average = (total - Double(social.stars) + Double(star)) / Double(social.ratings)
		}
		social.stars = star
		_social = social
	}

	private func _submit() {
		let body = _draft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !body.isEmpty else { return }
		_isPosting = true
		Task {
			defer { _isPosting = false }
			do {
				try await _account.comment(on: app.i, body: body, replyTo: _replyTo?.id)
				_draft = ""
				_replyTo = nil
				_social?.comments += 1
				await _loadThread()
			} catch {
				_show(error.localizedDescription)
			}
		}
	}

	/// Downloads need an Accretion account, like on the web store
	private func _needsAccount() -> Bool {
		guard _account.isSignedIn else {
			_isSigningIn = true
			return false
		}
		return true
	}

	private func _resolved(_ url: URL) async -> URL {
		await _account.downloadURL(for: app.i, fallback: url)
	}

	private func _show(_ message: String) {
		withAnimation { _toast = message }
		Task {
			try? await Task.sleep(nanoseconds: 2_200_000_000)
			withAnimation { if _toast == message { _toast = nil } }
		}
	}

	@ViewBuilder
	private func _toastView() -> some View {
		if let toast = _toast {
			Text(verbatim: toast)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(AccretionTheme.fg)
				.padding(.horizontal, 16)
				.padding(.vertical, 10)
				.background(AccretionTheme.raised, in: Capsule())
				.overlay(Capsule().stroke(AccretionTheme.line, lineWidth: 1))
				.padding(.bottom, 24)
				.transition(.move(edge: .bottom).combined(with: .opacity))
		}
	}
}

// MARK: - App lists ("See all", a developer's apps, saved apps)
struct StoreListRoute: Hashable {
	let title: String
	var category: String?
	var developer: String?
	/// A fixed list (a shelf's full contents), in order
	var ids: [String]?
	var saved = false
}

/// A full list of apps in the web store's card style, for "See all" and developer links.
struct StoreListView: View {
	@ObservedObject private var _store = StoreService.shared
	let route: StoreListRoute
	@State private var _shown = 60

	private var _apps: [StoreApp] {
		let all = _store.index?.apps ?? []
		if let ids = route.ids {
			let byID = Dictionary(all.map { ($0.i, $0) }, uniquingKeysWith: { first, _ in first })
			return ids.compactMap { byID[$0] }
		}
		let list = _store.sorted(
			all
				.filter { route.category == nil || $0.c == route.category }
				.filter { route.developer == nil || $0.d == route.developer }
				.filter { !route.saved || _store.isSaved($0) },
			by: .updated
		)
		// Saved: apps with an update first, like the website
		guard route.saved else { return list }
		return list.filter(_store.hasUpdate) + list.filter { !_store.hasUpdate($0) }
	}

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 12) {
				AccretionBackButton()
				HStack(alignment: .firstTextBaseline) {
					Text(verbatim: route.title)
						.font(.accretionDisplay(20))
						.foregroundStyle(AccretionTheme.fg)
					Spacer()
				}
				.padding(.top, 6)
				Text(verbatim: String.localized("%@ apps", arguments: _apps.count.formatted()))
					.font(.accretionMono(12, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
				ForEach(_apps.prefix(_shown)) { app in
					NavigationLink(value: app) { StoreAppCard(app: app) }
						.buttonStyle(.plain)
				}
				if _apps.count > _shown {
					Button(String.localized("Show more")) { _shown += 60 }
						.buttonStyle(AccretionButtonStyle(prominent: false))
						.frame(maxWidth: .infinity)
				} else if _apps.isEmpty {
					Text(verbatim: route.saved ? String.localized("Nothing saved yet. Tap Save on an app to keep it here.") : String.localized("Nothing here yet."))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar)
	}
}
