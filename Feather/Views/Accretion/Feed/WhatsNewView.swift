//
//  WhatsNewView.swift
//  Accretion
//

import SwiftUI

// MARK: - What's new
/// Accretion's own updates feed (the website's Feed → What's new): new Accretion versions and
/// Accretion Mods are posted automatically when they're published, admins add news. Likeable.
@MainActor
final class WhatsNewFeed: ObservableObject {
	static let shared = WhatsNewFeed()

	@Published private(set) var items: [AccretionAccount.Announcement] = []
	@Published private(set) var liked: Set<Int> = []
	@Published private(set) var canLoadMore = false
	@Published private(set) var error: String?
	private var _loadedAt: Date?
	private static let pageSize = 30

	func load(force: Bool = false) async {
		if !force, let loaded = _loadedAt, Date().timeIntervalSince(loaded) < 300 { return }
		do {
			let page = try await AccretionAccount.shared.announcements(limit: Self.pageSize)
			items = page
			canLoadMore = page.count == Self.pageSize
			liked = await AccretionAccount.shared.likedAnnouncements(page.map(\.id))
			error = nil
			_loadedAt = Date()
		} catch {
			self.error = String.localized("Couldn't load what's new: %@", arguments: error.localizedDescription)
		}
	}

	func loadMore() async {
		guard canLoadMore, let page = try? await AccretionAccount.shared.announcements(limit: Self.pageSize, offset: items.count) else { return }
		items += page
		canLoadMore = page.count == Self.pageSize
		liked.formUnion(await AccretionAccount.shared.likedAnnouncements(page.map(\.id)))
	}

	/// Like or unlike; the count updates right away and is put back if the server refuses
	func toggleLike(_ item: AccretionAccount.Announcement) async throws {
		let on = !liked.contains(item.id)
		_apply(item.id, on)
		do {
			try await AccretionAccount.shared.likeAnnouncement(item.id, on)
		} catch {
			_apply(item.id, !on)
			throw error
		}
	}

	private func _apply(_ id: Int, _ on: Bool) {
		if on { liked.insert(id) } else { liked.remove(id) }
		guard let index = items.firstIndex(where: { $0.id == id }) else { return }
		let item = items[index]
		items[index] = AccretionAccount.Announcement(
			id: item.id, kind: item.kind, title: item.title, body: item.body, app_id: item.app_id,
			version: item.version, link: item.link, created_at: item.created_at,
			likes: max(0, (item.likes ?? 0) + (on ? 1 : -1))
		)
	}
}

/// Navigation value for the full list
struct WhatsNewRoute: Hashable {}

/// One post: kind label, time, title, text, ♥ and Open
struct AnnouncementCard: View {
	@ObservedObject private var _feed = WhatsNewFeed.shared
	@ObservedObject private var _account = AccretionAccount.shared
	@ObservedObject private var _store = StoreService.shared
	let item: AccretionAccount.Announcement
	var compact = false
	var onNeedsAccount: () -> Void = {}
	var onError: (String) -> Void = { _ in }

	private var _label: (text: String, color: Color) {
		switch item.kind {
		case "release": return (String.localized("Accretion update"), AccretionTheme.accent)
		case "mod": return (String.localized("Accretion Mod"), AccretionTheme.accent)
		case "fix": return (String.localized("Fix"), AccretionTheme.accent2)
		default: return (String.localized("News"), AccretionTheme.good)
		}
	}

	var body: some View {
		let liked = _feed.liked.contains(item.id)
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 10) {
				AccretionBadge(text: _label.text, color: _label.color)
				Text(verbatim: StoreFormat.ago(item.created_at))
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
			}
			Text(verbatim: item.title)
				.font(.accretionDisplay(18))
				.foregroundStyle(AccretionTheme.fg)
			if !item.body.isEmpty {
				Text(verbatim: item.body)
					.font(.system(size: 14))
					.foregroundStyle(AccretionTheme.fg)
					.lineLimit(compact ? 4 : nil)
					.fixedSize(horizontal: false, vertical: true)
			}
			HStack(spacing: 6) {
				Button {
					guard _account.isSignedIn else { onNeedsAccount(); return }
					Task {
						do { try await _feed.toggleLike(item) } catch { onError(error.localizedDescription) }
					}
				} label: {
					Text(verbatim: "♥" + ((item.likes ?? 0) > 0 ? " \(item.likes ?? 0)" : ""))
						.foregroundStyle(liked ? Color(red: 244.0 / 255, green: 63.0 / 255, blue: 94.0 / 255) : AccretionTheme.muted)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
				.accessibilityLabel(liked ? String.localized("Unlike") : String.localized("Like"))
				if let app = item.app_id.flatMap({ id in _store.index?.apps.first { $0.i == id } }) {
					NavigationLink(value: app) {
						Text(verbatim: String.localized("Open"))
					}
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 14)
		.padding(.horizontal, 16)
		.accretionCard()
	}
}

/// Discover's "What's new" section: the three latest posts and See all
struct WhatsNewSection: View {
	@ObservedObject private var _feed = WhatsNewFeed.shared
	var onNeedsAccount: () -> Void

	var body: some View {
		if !_feed.items.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .firstTextBaseline, spacing: 12) {
					(Text(verbatim: String.localized("What's new")).font(.accretionDisplay(20)).foregroundColor(AccretionTheme.fg)
					 + Text(verbatim: "  " + String.localized("from Accretion")).font(.accretionMono(12, weight: .regular)).foregroundColor(AccretionTheme.muted))
					Spacer(minLength: 0)
					NavigationLink(value: WhatsNewRoute()) {
						Text(verbatim: String.localized("See all"))
							.font(.system(size: 14, weight: .semibold))
							.foregroundStyle(AccretionTheme.accent2)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(String.localized("See all of What's new"))
				}
				ForEach(_feed.items.prefix(3)) { item in
					AnnouncementCard(item: item, compact: true, onNeedsAccount: onNeedsAccount)
				}
			}
		}
	}
}

/// The full What's new list
struct WhatsNewView: View {
	@ObservedObject private var _feed = WhatsNewFeed.shared
	@State private var _isSigningIn = false
	@State private var _message: String?

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 12) {
				AccretionBackButton()
				Text(verbatim: String.localized("What's new"))
					.font(.accretionDisplay(28))
					.foregroundStyle(AccretionTheme.headline)
					.padding(.top, 6)
				Text(verbatim: String.localized("New Accretion versions, mods and fixes, posted automatically."))
					.foregroundStyle(AccretionTheme.muted)
				if let error = _feed.error {
					Text(verbatim: error).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				if let message = _message {
					Text(verbatim: message).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				ForEach(_feed.items) { item in
					AnnouncementCard(item: item, onNeedsAccount: { _isSigningIn = true }, onError: { _message = $0 })
				}
				if _feed.canLoadMore {
					Button(String.localized("Load more")) { Task { await _feed.loadMore() } }
						.buttonStyle(AccretionButtonStyle(prominent: false))
						.frame(maxWidth: .infinity)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar)
		.refreshable { await _feed.load(force: true) }
		.task { await _feed.load() }
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
	}
}
