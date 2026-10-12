//
//  CommunityViews.swift
//  Accretion
//

import SwiftUI

// MARK: - Shared pieces
private let _heart = Color(red: 244.0 / 255, green: 63.0 / 255, blue: 94.0 / 255)

/// Plain text with tappable https links, like the website's posts
private func _linked(_ text: String) -> AttributedString {
	var result = AttributedString(text)
	guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
	for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
		guard
			let url = match.url, url.scheme == "https",
			let range = Range(match.range, in: text),
			let lower = AttributedString.Index(range.lowerBound, within: result),
			let upper = AttributedString.Index(range.upperBound, within: result)
		else { continue }
		result[lower..<upper].link = url
		result[lower..<upper].underlineStyle = .single
	}
	return result
}

/// Page title and line under it, like the website's .view-head
private struct _ViewHead: View {
	let title: String
	let note: String

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: title)
				.font(.accretionDisplay(28))
				.foregroundStyle(AccretionTheme.headline)
			Text(verbatim: note)
				.font(.system(size: 15))
				.foregroundStyle(AccretionTheme.muted)
				.fixedSize(horizontal: false, vertical: true)
		}
		.padding(.top, 6)
	}
}

/// A feed post: avatar, name, @user, time, text, ♥ and Reply
struct FeedPostRow: View {
	let post: AccretionAccount.Post
	let liked: Bool
	var onLike: () -> Void
	var onReply: (() -> Void)?
	var onDelete: (() -> Void)?

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			StoreAvatar(letter: String((post.display_name?.isEmpty == false ? post.display_name! : post.username).prefix(1)).uppercased(), hex: post.color ?? "8B5CF6", size: 36)
			VStack(alignment: .leading, spacing: 4) {
				AccretionFlow(spacing: 6) {
					Text(verbatim: post.display_name?.isEmpty == false ? post.display_name! : post.username)
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(AccretionTheme.fg)
					Text(verbatim: "@\(post.username)")
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
					if let role = post.role, role == "admin" || role == "mod" {
						AccretionBadge(text: role, color: role == "admin" ? _heart : AccretionTheme.good)
					}
					if post.supporter == true {
						AccretionBadge(text: "♥ supporter", color: _heart)
					}
					Text(verbatim: "· " + StoreFormat.ago(post.created_at) + (post.edited_at != nil ? " · " + String.localized("edited") : ""))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
				}
				Text(_linked(post.body))
					.font(.system(size: 15))
					.foregroundStyle(AccretionTheme.fg)
					.tint(AccretionTheme.accent2)
					.fixedSize(horizontal: false, vertical: true)
				AccretionFlow(spacing: 4) {
					Button(action: onLike) {
						Text(verbatim: "♥" + ((post.likes ?? 0) > 0 ? " \(post.likes ?? 0)" : ""))
							.foregroundStyle(liked ? _heart : AccretionTheme.muted)
					}
					.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
					.accessibilityLabel(liked ? String.localized("Unlike") : String.localized("Like"))
					if let onReply {
						Button(String.localized("Reply") + ((post.replies ?? 0) > 0 ? " · \(post.replies ?? 0)" : ""), action: onReply)
							.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
					}
					if let onDelete {
						Button(String.localized("Delete"), action: onDelete)
							.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(.vertical, 12)
		.padding(.horizontal, 14)
		.accretionCard()
	}
}

/// "What's new?" box: text, count, Post
private struct _Composer: View {
	let placeholder: String
	var onPost: (String) async throws -> Void
	var onError: (String) -> Void
	@State private var _draft = ""
	@State private var _isPosting = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			TextField(placeholder, text: $_draft, axis: .vertical)
				.lineLimit(2...6)
				.foregroundStyle(AccretionTheme.fg)
			HStack {
				Text(verbatim: "\(_draft.count)/2000")
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
				Spacer()
				Button(String.localized("Post")) {
					let body = _draft.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !body.isEmpty else { return }
					_isPosting = true
					Task {
						defer { _isPosting = false }
						do {
							try await onPost(body)
							_draft = ""
						} catch {
							onError(error.localizedDescription)
						}
					}
				}
				.buttonStyle(AccretionButtonStyle(compact: true))
				.disabled(_isPosting || _draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || _draft.count > 2000)
			}
		}
		.padding(12)
		.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}
}

/// Flips a like on screen right away (calling it again puts it back, if the server refuses)
private func _toggleLike(_ post: AccretionAccount.Post, liked: inout Set<Int>, posts: inout [AccretionAccount.Post]) {
	let on = !liked.contains(post.id)
	if on { liked.insert(post.id) } else { liked.remove(post.id) }
	if let index = posts.firstIndex(where: { $0.id == post.id }) {
		let p = posts[index]
		posts[index] = AccretionAccount.Post(
			id: p.id, parent_id: p.parent_id, body: p.body, created_at: p.created_at, username: p.username,
			display_name: p.display_name, color: p.color, role: p.role,
			likes: max(0, (p.likes ?? 0) + (on ? 1 : -1)),
			replies: p.replies, author: p.author, hidden: p.hidden, edited_at: p.edited_at,
			supporter: p.supporter, app_id: p.app_id
		)
	}
}

// MARK: - Feed
/// Navigation value for the community feed
struct CommunityFeedRoute: Hashable {}

/// The website's Feed: What's new (Accretion's own posts), Everyone, and Following when signed in
struct CommunityFeedView: View {
	enum Tab: Hashable { case updates, everyone, following }

	@ObservedObject private var _account = AccretionAccount.shared
	@ObservedObject private var _whatsNew = WhatsNewFeed.shared
	@State private var _tab: Tab = .everyone
	@State private var _posts: [AccretionAccount.Post] = []
	@State private var _liked: Set<Int> = []
	@State private var _canLoadMore = false
	@State private var _loading = false
	@State private var _message: String?
	@State private var _isSigningIn = false
	@State private var _thread: AccretionAccount.Post?

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 12) {
				AccretionBackButton()
				_ViewHead(title: String.localized("Feed"), note: String.localized("What people are saying about apps, plus anything else on their mind."))
				if _tab != .updates {
					if _account.isSignedIn {
						_Composer(placeholder: String.localized("What's new?")) { body in
							try await _account.post(body)
							await _load(reset: true)
						} onError: { _message = $0 }
					} else {
						Button(String.localized("Sign in to post")) { _isSigningIn = true }
							.buttonStyle(AccretionButtonStyle(prominent: false))
					}
				}
				_tabs()
				if let message = _message {
					Text(verbatim: message).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				if _tab == .updates {
					ForEach(_whatsNew.items) { item in
						AnnouncementCard(item: item, onNeedsAccount: { _isSigningIn = true }, onError: { _message = $0 })
					}
					if _whatsNew.canLoadMore {
						Button(String.localized("Load more")) { Task { await _whatsNew.loadMore() } }
							.buttonStyle(AccretionButtonStyle(prominent: false))
							.frame(maxWidth: .infinity)
					}
				} else {
					if _posts.isEmpty && !_loading {
						Text(verbatim: _tab == .following
							? String.localized("Nothing yet from people you follow. Find people in comments and tap Follow.")
							: String.localized("No posts yet. Say hi!"))
							.font(.system(size: 14))
							.foregroundStyle(AccretionTheme.muted)
							.padding(.vertical, 12)
					}
					ForEach(_posts) { post in
						FeedPostRow(
							post: post,
							liked: _liked.contains(post.id),
							onLike: { _like(post) },
							onReply: { _thread = post },
							onDelete: post.author != nil && post.author == _account.userID ? { _delete(post) } : nil
						)
					}
					if _canLoadMore {
						Button(String.localized("Load more")) { Task { await _load(reset: false) } }
							.buttonStyle(AccretionButtonStyle(prominent: false))
							.frame(maxWidth: .infinity)
							.disabled(_loading)
					}
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar)
		.refreshable { await _reload() }
		.task(id: _tab) { await _reload() }
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
		.sheet(item: $_thread) { post in
			NavigationStack { FeedThreadView(post: post) }
		}
	}

	private func _tabs() -> some View {
		HStack(spacing: 4) {
			_tabButton(String.localized("What's new"), .updates)
			_tabButton(String.localized("Everyone"), .everyone)
			if _account.isSignedIn { _tabButton(String.localized("Following"), .following) }
		}
	}

	private func _tabButton(_ title: String, _ tab: Tab) -> some View {
		Button {
			AccretionHaptics.select()
			withAnimation(.easeOut(duration: 0.2)) { _tab = tab }
		} label: {
			Text(verbatim: title)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(_tab == tab ? AccretionTheme.fg : AccretionTheme.muted)
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(_tab == tab ? AccretionTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(_tab == tab ? .isSelected : [])
	}

	private func _reload() async {
		_message = nil
		if _tab == .updates {
			await _whatsNew.load(force: true)
			_message = _whatsNew.error
		} else {
			await _load(reset: true)
		}
	}

	private func _load(reset: Bool) async {
		_loading = true
		defer { _loading = false }
		do {
			let page = try await _account.feed(following: _tab == .following, offset: reset ? 0 : _posts.count)
			_posts = reset ? page : _posts + page
			_canLoadMore = page.count == AccretionAccount.feedPageSize
			_liked.formUnion(await _account.likedPosts(page.map(\.id)))
		} catch {
			_message = String.localized("Couldn't load the feed: %@", arguments: error.localizedDescription)
		}
	}

	private func _like(_ post: AccretionAccount.Post) {
		guard _account.isSignedIn else { _isSigningIn = true; return }
		let on = !_liked.contains(post.id)
		_toggleLike(post, liked: &_liked, posts: &_posts)
		Task {
			do { try await _account.likePost(post.id, on) } catch {
				_toggleLike(post, liked: &_liked, posts: &_posts)
				_message = error.localizedDescription
			}
		}
	}

	private func _delete(_ post: AccretionAccount.Post) {
		ConfirmDelete.ask(String.localized("Delete this post?")) {
			Task {
				do {
					try await _account.deletePost(post.id)
					_posts.removeAll { $0.id == post.id }
				} catch { _message = error.localizedDescription }
			}
		}
	}
}

/// One post with its replies and a reply box
struct FeedThreadView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _account = AccretionAccount.shared
	let post: AccretionAccount.Post
	@State private var _replies: [AccretionAccount.Post] = []
	@State private var _liked: Set<Int> = []
	@State private var _message: String?
	@State private var _isSigningIn = false

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 12) {
				FeedPostRow(post: post, liked: _liked.contains(post.id), onLike: { _like(post) })
				if let message = _message {
					Text(verbatim: message).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				ForEach(_replies) { reply in
					FeedPostRow(
						post: reply,
						liked: _liked.contains(reply.id),
						onLike: { _like(reply) },
						onDelete: reply.author != nil && reply.author == _account.userID ? { _delete(reply) } : nil
					)
					.padding(.leading, 24)
				}
				if _account.isSignedIn {
					_Composer(placeholder: String.localized("Reply to @%@", arguments: post.username)) { body in
						try await _account.post(body, replyTo: post.id)
						await _load()
					} onError: { _message = $0 }
				} else {
					Button(String.localized("Sign in to reply")) { _isSigningIn = true }
						.buttonStyle(AccretionButtonStyle(prominent: false))
				}
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Replies"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button(String.localized("Done")) { _dismiss() }
			}
		}
		.task { await _load() }
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
	}

	private func _load() async {
		do {
			_replies = try await _account.replies(to: post.id)
			_liked = await _account.likedPosts([post.id] + _replies.map(\.id))
		} catch {
			_message = String.localized("Couldn't load replies: %@", arguments: error.localizedDescription)
		}
	}

	private func _like(_ target: AccretionAccount.Post) {
		guard _account.isSignedIn else { _isSigningIn = true; return }
		let on = !_liked.contains(target.id)
		Task {
			do {
				try await _account.likePost(target.id, on)
				await _load()
			} catch { _message = error.localizedDescription }
		}
	}

	private func _delete(_ target: AccretionAccount.Post) {
		ConfirmDelete.ask(String.localized("Delete this reply?")) {
			Task {
				do { try await _account.deletePost(target.id); await _load() } catch { _message = error.localizedDescription }
			}
		}
	}
}

// MARK: - Notifications
struct NotificationsRoute: Hashable {}

/// Likes, replies and follows, newest first; opening the list marks them read, like the website
struct NotificationsView: View {
	@ObservedObject private var _account = AccretionAccount.shared
	@State private var _items: [AccretionAccount.Notice] = []
	@State private var _message: String?
	@State private var _loaded = false

	var body: some View {
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 10) {
				AccretionBackButton()
				_ViewHead(title: String.localized("Notifications"), note: String.localized("Likes, replies and new followers."))
				if let message = _message {
					Text(verbatim: message).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				if _loaded && _items.isEmpty && _message == nil {
					Text(verbatim: String.localized("Nothing yet."))
						.font(.system(size: 14))
						.foregroundStyle(AccretionTheme.muted)
						.padding(.vertical, 12)
				}
				ForEach(_items) { item in
					_row(item)
				}
			}
			.padding(.horizontal, 16)
			.padding(.top, 8)
			.padding(.bottom, 40)
		}
		.accretionBackground()
		.toolbar(.hidden, for: .navigationBar)
		.refreshable { await _load() }
		.task { await _load() }
	}

	private func _row(_ item: AccretionAccount.Notice) -> some View {
		let name = item.actor.map { $0.display_name?.isEmpty == false ? $0.display_name! : $0.username } ?? String.localized("Someone")
		let verb: String
		switch item.kind {
		case "like": verb = String.localized("liked your post")
		case "reply": verb = String.localized("replied to you")
		case "follow": verb = String.localized("followed you")
		default: verb = item.kind
		}
		return HStack(spacing: 12) {
			StoreAvatar(letter: String(name.prefix(1)).uppercased(), hex: item.actor?.color ?? "8B5CF6", size: 32)
			(Text(verbatim: name).bold().foregroundColor(AccretionTheme.fg) + Text(verbatim: " " + verb).foregroundColor(AccretionTheme.muted))
				.font(.system(size: 14))
			Spacer(minLength: 0)
			Text(verbatim: StoreFormat.ago(item.created_at))
				.font(.accretionMono(11, weight: .regular))
				.foregroundStyle(AccretionTheme.muted)
			if !item.read {
				Circle().fill(AccretionTheme.accent).frame(width: 7, height: 7)
			}
		}
		.padding(12)
		.accretionCard()
	}

	private func _load() async {
		guard _account.isSignedIn else {
			_message = String.localized("Sign in to see your notifications.")
			return
		}
		do {
			_items = try await _account.notifications()
			_message = nil
			_loaded = true
			if _items.contains(where: { !$0.read }) { await _account.markNotificationsRead() }
		} catch {
			_message = String.localized("Couldn't load notifications: %@", arguments: error.localizedDescription)
		}
	}
}

// MARK: - Sources
struct StoreSourcesRoute: Hashable {}

/// The website's Sources page: every source that feeds the store, with how many apps it supplies
struct StoreSourcesView: View {
	@ObservedObject private var _store = StoreService.shared
	@State private var _copied: String?

	private var _rows: [(index: Int, source: StoreSource, count: Int)] {
		guard let index = _store.index else { return [] }
		var counts: [Int: Int] = [:]
		for app in index.apps { counts[app.o, default: 0] += 1 }
		return index.sources.enumerated()
			.map { (index: $0.offset, source: $0.element, count: counts[$0.offset] ?? 0) }
			.sorted {
				let a = ($0.source.core == true ? 1 : 0, $0.count), b = ($1.source.core == true ? 1 : 0, $1.count)
				return a != b ? a > b : $0.source.name.localizedCaseInsensitiveCompare($1.source.name) == .orderedAscending
			}
	}

	var body: some View {
		let rows = _rows
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 10) {
				AccretionBackButton()
				_ViewHead(
					title: String.localized("Sources"),
					note: String.localized("%@ sources feed Accretion. \"Apps\" counts the apps where that source has the newest version.", arguments: rows.count.formatted())
				)
				ForEach(rows, id: \.index) { row in
					VStack(alignment: .leading, spacing: 8) {
						HStack(spacing: 8) {
							Text(verbatim: row.source.name)
								.font(.system(size: 15, weight: .semibold))
								.foregroundStyle(AccretionTheme.fg)
								.lineLimit(1)
							if row.source.core == true { AccretionBadge(text: "core", color: AccretionTheme.accent2) }
							Spacer(minLength: 0)
							(Text(verbatim: row.count.formatted()).bold().foregroundColor(AccretionTheme.fg)
							 + Text(verbatim: " " + String.localized("apps")).foregroundColor(AccretionTheme.muted))
								.font(.accretionMono(13, weight: .regular))
						}
						Text(verbatim: row.source.url)
							.font(.accretionMono(11.5, weight: .regular))
							.foregroundStyle(AccretionTheme.muted)
							.lineLimit(1)
							.truncationMode(.middle)
						HStack(spacing: 8) {
							if row.count > 0 {
								NavigationLink(value: StoreListRoute(title: row.source.name, source: row.index)) {
									Text(verbatim: String.localized("Browse"))
								}
								.buttonStyle(AccretionButtonStyle(prominent: false, compact: true))
							}
							Button(_copied == row.source.url ? String.localized("Copied") : String.localized("Copy")) {
								UIPasteboard.general.string = row.source.url
								AccretionHaptics.select()
								_copied = row.source.url
							}
							.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
						}
					}
					.padding(14)
					.accretionCard()
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
