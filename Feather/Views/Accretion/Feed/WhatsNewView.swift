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
		case "release": return (String.localized("Accretion update"), AccretionTheme.accentText)
		case "mod": return (String.localized("Accretion Mod"), AccretionTheme.accentText)
		case "fix": return (String.localized("Fix"), AccretionTheme.link)
		default: return (String.localized("News"), AccretionTheme.good)
		}
	}

	var body: some View {
		let liked = _feed.liked.contains(item.id)
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 10) {
				AccretionBadge(text: _label.text, color: _label.color)
				Text(verbatim: StoreFormat.ago(item.created_at))
					.accretionFont(13)
					.foregroundStyle(AccretionTheme.muted)
			}
			Text(verbatim: item.title)
				.font(.accretionDisplay(18))
				.foregroundStyle(AccretionTheme.fg)
			if !item.body.isEmpty {
				Text(verbatim: item.body)
					.accretionFont(14)
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
						.foregroundStyle(liked ? AccretionTheme.rose : AccretionTheme.muted)
						.accretionNumberRoll(item.likes ?? 0)
						.accretionPop(liked)
				}
				.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
				.accessibilityLabel(liked ? String.localized("Unlike") : String.localized("Like"))
				if let app = item.app_id.flatMap({ id in _store.index?.apps.first { $0.i == id } }) {
					NavigationLink(value: app) {
						Text(verbatim: String.localized("Open"))
					}
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
					.prefetchesDetail(app)
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 14)
		.padding(.horizontal, 16)
		.accretionCard()
	}
}

/// Discover's "What's new": one row with the newest post (title and age) that opens the Feed on
/// its What's new tab, where the full posts are. Owner's call (2026-10-19): the cards took too
/// much of Discover.
struct WhatsNewSection: View {
	@ObservedObject private var _feed = WhatsNewFeed.shared

	var body: some View {
		if let latest = _feed.items.first {
			NavigationLink(value: CommunityFeedRoute(whatsNew: true)) {
				HStack(spacing: 12) {
					Image(systemName: "sparkles")
						.accretionFont(17, weight: .semibold)
						.foregroundStyle(AccretionTheme.accentText)
						.accessibilityHidden(true)
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: String.localized("What's new"))
							.font(.accretionDisplay(15, weight: .semibold))
							.foregroundStyle(AccretionTheme.fg)
						Text(verbatim: latest.title + " · " + StoreFormat.ago(latest.created_at))
							.accretionFont(13)
							.foregroundStyle(AccretionTheme.muted)
							.lineLimit(1)
					}
					Spacer(minLength: 0)
					Image(systemName: "chevron.right")
						.accretionFont(13, weight: .semibold)
						.foregroundStyle(AccretionTheme.muted)
						.accessibilityHidden(true)
				}
				.padding(.vertical, 12)
				.padding(.horizontal, 14)
				.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
				.accretionCard()
				.contentShape(Rectangle())
			}
			.buttonStyle(AccretionPressStyle())
			.accessibilityElement(children: .combine)
			.accessibilityHint(String.localized("Opens What's new in the Feed"))
		}
	}
}
