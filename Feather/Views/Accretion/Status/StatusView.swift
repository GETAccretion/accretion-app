//
//  StatusView.swift
//  Accretion
//

import SwiftUI

// MARK: - Status
/// The website's #/status page: the whole index at a glance, from data/stats.json (rebuilt every
/// 6 hours): apps, sources up, listings scanned, duplicates, updates, dead links, failed spec,
/// categories, monthly growth, sizes, biggest sources and just-updated apps.
struct StoreStatus: Decodable {
	struct Source: Decodable, Hashable { let name: String; let apps: Int }
	struct Recent: Decodable, Hashable { let name: String; let version: String; let date: String }
	struct Month: Decodable, Hashable { let month: String; let apps: Int }

	let apps: Int?
	let curated_apps: Int?
	let sources_total: Int?
	let sources_failed: Int?
	let sources_cached: Int?
	let sources_discovered: Int?
	let listings: Int?
	let duplicates: Int?
	let rejected: Int?
	let excluded: Int?
	let dead_links_removed: Int?
	let developers: Int?
	let updated_7d: Int?
	let updated_30d: Int?
	let size_mb: Double?
	let curated_size_mb: Double?
	let updated: String?
	let categories: [String: Int]?
	let top_sources: [Source]?
	let recent: [Recent]?
	let timeline: [Month]?
}

struct StatusRoute: Hashable {}

struct StatusView: View {
	@State private var _status: StoreStatus?
	@State private var _failed = false
	/// Moderators and admins also see community numbers
	@State private var _community: AccretionAccount.CommunityStats?

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				AccretionBackButton()
				if let status = _status {
					_content(status)
				} else if _failed {
					Text(verbatim: String.localized("Couldn't load the status. Check your connection."))
						.foregroundStyle(AccretionTheme.muted)
				} else {
					ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
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

	private func _load() async {
		var request = URLRequest(url: StoreService.base.appendingPathComponent("data/stats.json"))
		request.cachePolicy = .reloadIgnoringLocalCacheData
		guard
			let (data, _) = try? await URLSession.shared.data(for: request),
			let status = try? JSONDecoder().decode(StoreStatus.self, from: data)
		else {
			_failed = _status == nil
			return
		}
		_status = status
		if let role = await AccretionAccount.shared.myRole(), role == "mod" || role == "admin" {
			_community = try? await AccretionAccount.shared.communityStats()
		}
	}

	@ViewBuilder
	private func _content(_ s: StoreStatus) -> some View {
		let down = (s.sources_failed ?? 0) + (s.sources_cached ?? 0)
		let total = s.sources_total ?? 0
		HStack(spacing: 8) {
			LiveDot(tone: .freshness(s.updated))
			Text(verbatim: (String.localized("Live index") + " · " + String.localized("build %@", arguments: s.updated ?? "")).uppercased())
				.font(.accretionMono(12, weight: .regular))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
		}
		.padding(.top, 6)
		Text(verbatim: String.localized("Status"))
			.font(.accretionDisplay(28))
			.foregroundStyle(AccretionTheme.headline)
		Text(verbatim: String.localized("The whole index at a glance. Rebuilt every 6 hours from every source."))
			.foregroundStyle(AccretionTheme.muted)
			.fixedSize(horizontal: false, vertical: true)

		Grid(horizontalSpacing: 10, verticalSpacing: 10) {
			GridRow {
				_tile(String.localized("Apps"), s.apps, String.localized("newest build of each"))
				_tile(String.localized("Sources"), nil, String.localized("%@ auto-discovered", arguments: (s.sources_discovered ?? 0).formatted()), text: "\(max(0, total - down))/\(total)")
			}
			GridRow {
				_tile(String.localized("Listings scanned"), s.listings, (s.apps ?? 0) > 0 ? String.localized("%@ per app", arguments: String(format: "%.1f", Double(s.listings ?? 0) / Double(s.apps ?? 1))) : nil)
				_tile(String.localized("Duplicates resolved"), s.duplicates, String.localized("apps found on 2+ sources"))
			}
			GridRow {
				_tile(String.localized("Updated 7d"), s.updated_7d, nil, tone: AccretionTheme.good)
				_tile(String.localized("Updated 30d"), s.updated_30d, nil)
			}
			GridRow {
				_tile(String.localized("Dead links purged"), s.dead_links_removed, nil)
				_tile(String.localized("Failed spec"), s.rejected, nil, tone: AccretionTheme.warn)
			}
		}

		AccretionSection(String.localized("Categories")) { _bars(s.categories ?? [:]) }
		AccretionSection(nil) { _growth(s, down: down) }
		if let sources = s.top_sources, !sources.isEmpty {
			AccretionSection(String.localized("Biggest sources")) {
				ForEach(sources, id: \.self) { source in
					_row(source.name, String.localized("%@ apps", arguments: source.apps.formatted()))
				}
			}
		}
		if let community = _community {
			_communitySection(community)
		}
		if let recent = s.recent, !recent.isEmpty {
			AccretionSection(String.localized("Just updated")) {
				ForEach(recent, id: \.self) { app in
					_row("\(app.name) \(app.version)", StoreFormat.ago(app.date))
				}
			}
		}
	}

	@ViewBuilder
	private func _communitySection(_ c: AccretionAccount.CommunityStats) -> some View {
		HStack(spacing: 10) {
			Text(verbatim: String.localized("Community"))
				.font(.accretionDisplay(20))
				.foregroundStyle(AccretionTheme.fg)
			AccretionBadge(text: "moderators only", color: AccretionTheme.accent)
		}
		.padding(.top, 8)
		let n: (Int?) -> String = { ($0 ?? 0).formatted() }
		Grid(horizontalSpacing: 10, verticalSpacing: 10) {
			GridRow {
				_tile(String.localized("Users"), c.users, String.localized("+%@ this week · +%@ in 30 days", arguments: n(c.new_7d), n(c.new_30d)))
				_tile(String.localized("Active 30d"), c.active_30d, String.localized("%@ signed in this week", arguments: n(c.signed_in_7d)), tone: AccretionTheme.good)
			}
			GridRow {
				_tile(String.localized("Downloads"), c.downloads, String.localized("%@ this week · %@ people in 30 days", arguments: n(c.downloads_7d), n(c.downloaders_30d)))
				_tile(String.localized("Personal links"), c.download_keys, String.localized("%@ downloads by link in 30 days", arguments: n(c.downloads_by_key_30d)))
			}
			GridRow {
				_tile(String.localized("Posts"), c.posts, String.localized("%@ comments · %@ this week", arguments: n(c.comments), n(c.posts_7d)))
				_tile(String.localized("Likes"), c.likes, String.localized("%@ ratings · %@ follows", arguments: n(c.ratings), n(c.follows)))
			}
			GridRow {
				_tile(String.localized("Open reports"), c.reports_open, String.localized("%@ banned", arguments: n(c.banned)), tone: (c.reports_open ?? 0) > 0 ? AccretionTheme.warn : nil)
				_tile(String.localized("Backups"), c.backups, String.localized("%@ accounts", arguments: n(c.backup_accounts)))
			}
			GridRow {
				_tile(String.localized("Store, 7 days"), c.views_7d, String.localized("views · %@ installs", arguments: n(c.installs_7d)))
				_tile(String.localized("Team"), c.moderators, String.localized("moderators and admins · %@ ♥ supporters", arguments: n(c.supporters)))
			}
		}
		if let days = c.signups_by_day, days.count >= 2 {
			AccretionSection(String.localized("Sign-ups, 30 days")) {
				_GrowthChart(values: days.map(\.n)).frame(height: 80)
			}
		}
		if let top = c.top_downloads_30d, !top.isEmpty {
			AccretionSection(String.localized("Most downloaded, 30 days")) {
				ForEach(top, id: \.self) { item in
					_row(StoreService.shared.index?.apps.first { $0.i == item.app }?.n ?? item.app, item.n.formatted())
				}
			}
		}
	}

	private func _tile(_ label: String, _ value: Int?, _ note: String?, tone: Color? = nil, text: String? = nil) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: label.uppercased())
				.font(.accretionMono(10.5, weight: .regular))
				.tracking(1)
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: text ?? value.map { $0.formatted() } ?? "–")
				.font(.accretionDisplay(24))
				.foregroundStyle(tone ?? AccretionTheme.fg)
			if let note {
				Text(verbatim: note)
					.font(.accretionMono(11, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(2)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.padding(14)
		.background(AccretionTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
	}

	/// The five biggest categories, then the rest together, as bars
	private func _bars(_ categories: [String: Int]) -> some View {
		let sorted = categories.sorted { $0.value > $1.value }
		var rows = Array(sorted.prefix(5)).map { (StoreService.categoryNames[$0.key] ?? $0.key, $0.value) }
		let rest = sorted.dropFirst(5).reduce(0) { $0 + $1.value }
		if rest > 0 { rows.append((String.localized("Rest"), rest)) }
		let most = max(1, rows.map { $0.1 }.max() ?? 1)
		return VStack(spacing: 8) {
			ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
				let (name, count) = row
				HStack(spacing: 10) {
					Text(verbatim: name)
						.font(.accretionMono(12, weight: .regular))
						.foregroundStyle(AccretionTheme.fg)
						.frame(width: 100, alignment: .leading)
						.lineLimit(1)
					GeometryReader { geo in
						ZStack(alignment: .leading) {
							Capsule().fill(AccretionTheme.raised)
							Capsule()
								.fill(LinearGradient(colors: [AccretionTheme.accent, AccretionTheme.accent2], startPoint: .leading, endPoint: .trailing))
								.frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(most)))
						}
					}
					.frame(height: 8)
					Text(verbatim: count.formatted())
						.font(.accretionMono(12, weight: .regular))
						.foregroundStyle(AccretionTheme.muted)
						.frame(width: 50, alignment: .trailing)
				}
				.accessibilityElement(children: .combine)
			}
		}
	}

	@ViewBuilder
	private func _growth(_ s: StoreStatus, down: Int) -> some View {
		let points = s.timeline ?? []
		HStack(alignment: .firstTextBaseline) {
			Text(verbatim: String.localized("Growth").uppercased())
				.font(.accretionMono(11, weight: .medium))
				.tracking(1.1)
				.foregroundStyle(AccretionTheme.muted)
			Spacer()
			Text(verbatim: String.localized("%@ apps", arguments: (s.apps ?? 0).formatted()))
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(AccretionTheme.fg)
		}
		_GrowthChart(values: points.map(\.apps))
			.frame(height: 100)
			.accessibilityLabel(String.localized("Apps per month"))
		HStack {
			Text(verbatim: points.first?.month ?? "")
			Spacer()
			Text(verbatim: String.localized("now"))
		}
		.font(.accretionMono(11, weight: .regular))
		.foregroundStyle(AccretionTheme.muted)
		if points.count >= 2, let last = points.last {
			let yearAgo = points.suffix(13).first ?? points[0]
			Text(verbatim: String.localized("+%@ new apps in 12 months", arguments: (last.apps - yearAgo.apps).formatted()))
				.font(.accretionMono(12, weight: .regular))
				.foregroundStyle(AccretionTheme.muted)
		}
		HStack(spacing: 6) {
			Text(verbatim: String.localized("core %@ apps / %@ MB · full %@ MB ·", arguments: (s.curated_apps ?? 0).formatted(), String(s.curated_size_mb ?? 0), String(s.size_mb ?? 0)))
				.foregroundStyle(AccretionTheme.muted)
			Text(verbatim: down == 0 ? String.localized("all sources up") : String.localized("%@ sources down", arguments: String(down)))
				.foregroundStyle(down == 0 ? AccretionTheme.good : AccretionTheme.warn)
		}
		.font(.accretionMono(11, weight: .regular))
	}

	private func _row(_ name: String, _ detail: String) -> some View {
		HStack(spacing: 10) {
			Text(verbatim: name)
				.font(.system(size: 14))
				.foregroundStyle(AccretionTheme.fg)
				.lineLimit(1)
			Spacer(minLength: 0)
			Text(verbatim: detail)
				.font(.accretionMono(12, weight: .regular))
				.foregroundStyle(AccretionTheme.muted)
		}
	}
}

/// Apps per month as a line with a soft fill, like the website's growth chart
private struct _GrowthChart: View {
	let values: [Int]

	var body: some View {
		GeometryReader { geo in
			let points = _points(in: geo.size)
			if points.count >= 2 {
				ZStack {
					Path { path in
						path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
						points.forEach { path.addLine(to: $0) }
						path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
						path.closeSubpath()
					}
					.fill(AccretionTheme.accent.opacity(0.22))
					Path { path in
						path.move(to: points[0])
						points.dropFirst().forEach { path.addLine(to: $0) }
					}
					.stroke(AccretionTheme.accent2, lineWidth: 2)
					Circle()
						.fill(AccretionTheme.accent2)
						.frame(width: 7, height: 7)
						.position(points[points.count - 1])
				}
			}
		}
	}

	private func _points(in size: CGSize) -> [CGPoint] {
		guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
		let span = CGFloat(max(1, high - low))
		return values.enumerated().map { index, value in
			CGPoint(
				x: 4 + CGFloat(index) / CGFloat(values.count - 1) * (size.width - 8),
				y: size.height - 4 - CGFloat(value - low) / span * (size.height - 12)
			)
		}
	}
}
