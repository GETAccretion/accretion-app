//
//  CommunityViews.swift
//  Accretion
//

import SwiftUI

// MARK: - Shared pieces
private let _heart = Color(red: 244.0 / 255, green: 63.0 / 255, blue: 94.0 / 255)

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

// MARK: - Post
/// One post, the same everywhere (app comments, the feed, replies): avatar, name, @user, badges,
/// time, text, the app it's about, ♥, Reply, and a ••• menu with Follow, Report, Hide and Delete.
/// Actions that are nil aren't shown.
struct PostRow: View {
	@ObservedObject private var _store = StoreService.shared
	let post: AccretionAccount.Post
	let liked: Bool
	/// nil: no Follow item (your own post, or signed out)
	var following: Bool?
	/// false inside a list that has its own background (an app's Comments)
	var card = true
	var onLike: () -> Void
	var onReply: (() -> Void)?
	var onFollow: (() -> Void)?
	var onReport: (() -> Void)?
	var onHide: (() -> Void)?
	var onDelete: (() -> Void)?

	private var _name: String { post.display_name?.isEmpty == false ? post.display_name! : post.username }

	var body: some View {
		let row = HStack(alignment: .top, spacing: 12) {
			StoreAvatar(letter: String(_name.prefix(1)).uppercased(), hex: post.color ?? "8B5CF6", size: 36)
			VStack(alignment: .leading, spacing: 4) {
				AccretionFlow(spacing: 6) {
					Text(verbatim: _name)
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
					if post.hidden == true {
						AccretionBadge(text: "hidden", color: AccretionTheme.warn)
					}
					Text(verbatim: "· " + StoreFormat.ago(post.created_at) + (post.edited_at != nil ? " · " + String.localized("edited") : ""))
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.muted)
				}
				Text(accretionLinked(post.body))
					.font(.system(size: 15))
					.foregroundStyle(AccretionTheme.fg)
					.tint(AccretionTheme.accent2)
					.fixedSize(horizontal: false, vertical: true)
				if let app = post.app_id.flatMap({ id in _store.index?.apps.first { $0.i == id } }) {
					NavigationLink(value: app) {
						HStack(spacing: 8) {
							StoreAppIcon(url: app.iconURL, size: 22, radius: 6)
							Text(verbatim: app.n)
								.font(.system(size: 13, weight: .semibold))
								.foregroundStyle(AccretionTheme.fg)
								.lineLimit(1)
							Text(verbatim: "›").foregroundStyle(AccretionTheme.muted)
						}
						.padding(.vertical, 5)
						.padding(.horizontal, 8)
						.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
						.overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
					}
					.buttonStyle(AccretionPressStyle())
					.accessibilityLabel(String.localized("About %@", arguments: app.n))
				}
				_actions()
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		if card {
			row.padding(.vertical, 12).padding(.horizontal, 14).accretionCard()
		} else {
			row.padding(.vertical, 12).padding(.horizontal, 4)
		}
	}

	private func _actions() -> some View {
		HStack(spacing: 4) {
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
			if onFollow != nil || onReport != nil || onHide != nil || onDelete != nil {
				Menu {
					if let onFollow, let following {
						Button(following ? String.localized("Unfollow @%@", arguments: post.username) : String.localized("Follow @%@", arguments: post.username), action: onFollow)
					}
					if let onReport {
						Button(String.localized("Report"), action: onReport)
					}
					if let onHide {
						Button(post.hidden == true ? String.localized("Unhide") : String.localized("Hide"), action: onHide)
					}
					if let onDelete {
						Button(String.localized("Delete"), role: .destructive, action: onDelete)
					}
				} label: {
					Text(verbatim: "•••")
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(AccretionTheme.muted)
						.frame(minWidth: 34, minHeight: 34)
				}
				.accessibilityLabel(String.localized("More"))
			}
		}
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

/// Admins: post News to What's new, like the website's "Post news" form
private struct _NewsComposer: View {
	var onPosted: () async -> Void
	var onError: (String) -> Void
	@State private var _title = ""
	@State private var _body = ""
	@State private var _isPosting = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(verbatim: String.localized("Post news"))
				.font(.accretionDisplay(16))
				.foregroundStyle(AccretionTheme.fg)
			TextField(String.localized("Title"), text: $_title)
				.foregroundStyle(AccretionTheme.fg)
			TextField(String.localized("What changed?"), text: $_body, axis: .vertical)
				.lineLimit(3...8)
				.foregroundStyle(AccretionTheme.fg)
			HStack {
				Spacer()
				Button(String.localized("Post")) {
					let title = _title.trimmingCharacters(in: .whitespacesAndNewlines)
					guard !title.isEmpty else { onError(String.localized("Add a title")); return }
					_isPosting = true
					Task {
						defer { _isPosting = false }
						do {
							try await AccretionAccount.shared.postNews(title: String(title.prefix(120)), body: String(_body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000)))
							_title = ""
							_body = ""
							await onPosted()
						} catch {
							onError(error.localizedDescription)
						}
					}
				}
				.buttonStyle(AccretionButtonStyle(compact: true))
				.disabled(_isPosting)
			}
		}
		.padding(12)
		.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}
}

/// The website's report box, as an alert: a reason, then Report
private struct _ReportAlert: ViewModifier {
	@Binding var post: AccretionAccount.Post?
	var onDone: (String) -> Void
	@State private var _reason = ""

	func body(content: Content) -> some View {
		content.alert(String.localized("Report this post"), isPresented: Binding(get: { post != nil }, set: { if !$0 { post = nil } })) {
			TextField(String.localized("What's wrong? (spam, harassment, malware link…)"), text: $_reason)
			Button(String.localized("Cancel"), role: .cancel) { post = nil; _reason = "" }
			Button(String.localized("Report")) {
				guard let target = post else { return }
				let reason = _reason.trimmingCharacters(in: .whitespacesAndNewlines)
				post = nil
				_reason = ""
				guard !reason.isEmpty else { return }
				Task {
					do {
						try await AccretionAccount.shared.report(post: target.id, reason: reason)
						onDone(String.localized("Thanks. A moderator will look at it."))
					} catch { onDone(error.localizedDescription) }
				}
			}
		}
	}
}

extension View {
	fileprivate func reportAlert(_ post: Binding<AccretionAccount.Post?>, onDone: @escaping (String) -> Void) -> some View {
		modifier(_ReportAlert(post: post, onDone: onDone))
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

/// Who you are, for showing Follow, Delete and moderator actions on posts
@MainActor
final class CommunityViewer: ObservableObject {
	static let shared = CommunityViewer()
	@Published private(set) var following: Set<String> = []
	@Published private(set) var role: String?
	private var _loadedFor: String?

	var isModerator: Bool { role == "mod" || role == "admin" }

	func load() async {
		let account = AccretionAccount.shared
		guard account.isSignedIn else { following = []; role = nil; _loadedFor = nil; return }
		guard _loadedFor != account.userID else { return }
		following = await account.following()
		role = await account.myRole()
		_loadedFor = account.userID
	}

	func toggleFollow(_ userID: String) async throws {
		let on = !following.contains(userID)
		try await AccretionAccount.shared.follow(userID, on)
		if on { following.insert(userID) } else { following.remove(userID) }
	}
}

/// The ••• actions for a post, decided once for every screen
@MainActor
private struct _PostActions {
	let viewer: CommunityViewer
	let post: AccretionAccount.Post

	private var _mine: Bool { post.author != nil && post.author == AccretionAccount.shared.userID }

	var following: Bool? {
		guard AccretionAccount.shared.isSignedIn, !_mine, let author = post.author else { return nil }
		return viewer.following.contains(author)
	}
	var canReport: Bool { AccretionAccount.shared.isSignedIn && !_mine }
	var canHide: Bool { viewer.isModerator }
	var canDelete: Bool { _mine }
}

// MARK: - Feed
/// Navigation value for the community feed
struct CommunityFeedRoute: Hashable {}

/// The website's Feed: What's new (Accretion's own posts), Everyone, and Following when signed in
struct CommunityFeedView: View {
	enum Tab: Hashable { case updates, everyone, following }

	@ObservedObject private var _account = AccretionAccount.shared
	@ObservedObject private var _whatsNew = WhatsNewFeed.shared
	@ObservedObject private var _viewer = CommunityViewer.shared
	@State private var _tab: Tab = .everyone
	@State private var _posts: [AccretionAccount.Post] = []
	@State private var _liked: Set<Int> = []
	@State private var _canLoadMore = false
	@State private var _loading = false
	@State private var _message: String?
	@State private var _isSigningIn = false
	@State private var _thread: AccretionAccount.Post?
	@State private var _reporting: AccretionAccount.Post?

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
				} else if _viewer.role == "admin" {
					_NewsComposer {
						await _whatsNew.load(force: true)
					} onError: { _message = $0 }
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
							? String.localized("Nothing yet from people you follow. Tap ••• on a post to follow someone.")
							: String.localized("No posts yet. Say hi!"))
							.font(.system(size: 14))
							.foregroundStyle(AccretionTheme.muted)
							.padding(.vertical, 12)
					}
					ForEach(_posts) { post in
						_row(post)
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
		.task(id: _tab) {
			await _viewer.load()
			await _reload()
		}
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
		.sheet(item: $_thread) { post in
			NavigationStack { FeedThreadView(post: post) }
		}
		.reportAlert($_reporting) { _message = $0 }
	}

	private func _row(_ post: AccretionAccount.Post) -> some View {
		let actions = _PostActions(viewer: _viewer, post: post)
		return PostRow(
			post: post,
			liked: _liked.contains(post.id),
			following: actions.following,
			onLike: { _like(post) },
			onReply: { _thread = post },
			onFollow: actions.following == nil ? nil : { _follow(post) },
			onReport: actions.canReport ? { _reporting = post } : nil,
			onHide: actions.canHide ? { _hide(post) } : nil,
			onDelete: actions.canDelete ? { _delete(post) } : nil
		)
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

	private func _follow(_ post: AccretionAccount.Post) {
		guard let author = post.author else { return }
		Task {
			do { try await _viewer.toggleFollow(author) } catch { _message = error.localizedDescription }
		}
	}

	private func _hide(_ post: AccretionAccount.Post) {
		Task {
			do {
				try await _account.hidePost(post.id, !(post.hidden ?? false))
				await _load(reset: true)
			} catch { _message = error.localizedDescription }
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
	@ObservedObject private var _viewer = CommunityViewer.shared
	let post: AccretionAccount.Post
	@State private var _root: AccretionAccount.Post?
	@State private var _replies: [AccretionAccount.Post] = []
	@State private var _liked: Set<Int> = []
	@State private var _message: String?
	@State private var _isSigningIn = false
	@State private var _reporting: AccretionAccount.Post?

	var body: some View {
		let root = _root ?? post
		ScrollView {
			LazyVStack(alignment: .leading, spacing: 12) {
				_row(root)
				if let message = _message {
					Text(verbatim: message).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
				}
				ForEach(_replies) { reply in
					_row(reply).padding(.leading, 24)
				}
				if _account.isSignedIn {
					_Composer(placeholder: String.localized("Reply to @%@", arguments: root.username)) { body in
						try await _account.post(body, replyTo: root.id)
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
		.navigationDestination(for: StoreApp.self) { StoreAppView(app: $0) }
		.toolbar {
			ToolbarItem(placement: .confirmationAction) {
				Button(String.localized("Done")) { _dismiss() }
			}
		}
		.task {
			await _viewer.load()
			await _load()
		}
		.sheet(isPresented: $_isSigningIn) { AccountSheet() }
		.reportAlert($_reporting) { _message = $0 }
	}

	private func _row(_ target: AccretionAccount.Post) -> some View {
		let actions = _PostActions(viewer: _viewer, post: target)
		return PostRow(
			post: target,
			liked: _liked.contains(target.id),
			following: actions.following,
			onLike: { _like(target) },
			onFollow: actions.following == nil ? nil : {
				guard let author = target.author else { return }
				Task { do { try await _viewer.toggleFollow(author) } catch { _message = error.localizedDescription } }
			},
			onReport: actions.canReport ? { _reporting = target } : nil,
			onHide: actions.canHide ? {
				Task {
					do { try await _account.hidePost(target.id, !(target.hidden ?? false)); await _load() } catch { _message = error.localizedDescription }
				}
			} : nil,
			onDelete: actions.canDelete ? { _delete(target) } : nil
		)
	}

	/// A reply opened from a notification shows its whole thread, from the top post
	private func _load() async {
		do {
			var root = _root ?? post
			if let parent = root.parent_id, let top = try await _account.post(id: parent) {
				root = top
			}
			if let fresh = try await _account.post(id: root.id) { root = fresh }
			_root = root
			_replies = try await _account.replies(to: root.id)
			_liked = await _account.likedPosts([root.id] + _replies.map(\.id))
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
				do {
					try await _account.deletePost(target.id)
					if target.id == (_root ?? post).id { _dismiss() } else { await _load() }
				} catch { _message = error.localizedDescription }
			}
		}
	}
}

// MARK: - Notifications
struct NotificationsRoute: Hashable {}

/// Likes, replies and follows, newest first; opening the list marks them read, like the website.
/// Tapping a like or a reply opens that post's thread.
struct NotificationsView: View {
	@ObservedObject private var _account = AccretionAccount.shared
	@State private var _items: [AccretionAccount.Notice] = []
	@State private var _message: String?
	@State private var _loaded = false
	@State private var _thread: AccretionAccount.Post?

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
					if let postID = item.post_id {
						Button { _open(postID) } label: { _row(item) }
							.buttonStyle(AccretionPressStyle())
					} else {
						_row(item)
					}
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
		.sheet(item: $_thread) { post in
			NavigationStack { FeedThreadView(post: post) }
		}
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
				.multilineTextAlignment(.leading)
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

	private func _open(_ postID: Int) {
		Task {
			do {
				if let post = try await _account.post(id: postID) {
					_thread = post
				} else {
					_message = String.localized("That post was deleted.")
				}
			} catch {
				_message = error.localizedDescription
			}
		}
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
