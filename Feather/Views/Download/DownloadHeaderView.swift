//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine
import NimbleExtensions

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager
	/// Accretion: the ad card stays at least this long, even when the download finishes sooner
	private static let _minimumAdSeconds: UInt64 = 10
	@State private var _holdAd = false
	@State private var _holdToken = 0
	/// Accretion: Google's ad only while every app downloading is one of Accretion's own builds
	@State private var _googleAd = false

	var body: some View {
		ZStack {
			// Accretion: also while store, source or update downloads run, for the ad card below
			if !downloadManager.manualDownloads.isEmpty || _isDownloading || _holdAd {
				VStack {
					VStack(spacing: 12) {
						if let firstDownload = downloadManager.manualDownloads.first {
							DownloadItemView(download: firstDownload)
							
							if downloadManager.manualDownloads.count > 1 {
								HStack {
									Spacer()
									Text(verbatim: "+\(downloadManager.manualDownloads.count - 1)")
										.font(.caption)
										.foregroundColor(.secondary)
										.padding(.vertical, 4)
								}
							}
						}
						// Accretion: ad card while anything downloads (hidden for admins and supporters);
						// other sources' apps get the sponsor card instead of Google's ad
						AccretionAdCard(googleAd: _googleAd)
					}
					.padding(.horizontal)
				}
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.manualDownloads.count)
		.animation(.spring(), value: _isDownloading)
		.animation(.spring(), value: _holdAd)
		.onAppear { if _isDownloading { _googleAd = _ownBuildsOnly } }
		.onChange(of: downloadManager.downloads.count) { _ in
			// Accretion: decided while downloads run, kept through the 10-second hold afterwards
			if _isDownloading { _googleAd = _ownBuildsOnly }
		}
		.onChange(of: _isDownloading) { downloading in
			// Accretion: each new download restarts the 10-second minimum for the ad card
			guard downloading else { return }
			_googleAd = _ownBuildsOnly
			_holdToken += 1
			let token = _holdToken
			_holdAd = true
			Task { @MainActor in
				try? await Task.sleep(nanoseconds: Self._minimumAdSeconds * 1_000_000_000)
				if token == _holdToken { _holdAd = false }
			}
		}
	}

	/// Accretion: an app is downloading (not only a pasted link; archive exports don't count)
	private var _isDownloading: Bool {
		downloadManager.downloads.contains { !$0.onlyArchiving }
	}

	/// Accretion: every app downloading is one of Accretion's own builds (Accretion, Accretion Mods)
	private var _ownBuildsOnly: Bool {
		let active = downloadManager.downloads.filter { !$0.onlyArchiving }
		return !active.isEmpty && active.allSatisfy {
			AccretionBuildSelection.isOwnBuildDownload($0.url, host: AccretionAccount.accountHost)
		}
	}
}

struct DownloadItemView: View {
	let download: Download
	@State private var progress: Double = 0
	@State private var bytesDownloaded: Int64 = 0
	@State private var totalBytes: Int64 = 0
	@State private var unpackageProgress: Double = 0
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(download.fileName)
				.font(.subheadline)
				.lineLimit(1)
			
			ProgressView(value: overallProgress)
				.progressViewStyle(.linear)
			
			HStack {
				Text(verbatim: "\(Int(overallProgress * 100))%")
					.contentTransition(.numericText())
				Spacer()
				if totalBytes > 0 {
					Text(verbatim: "\($bytesDownloaded.wrappedValue.formattedByteCount) / \(totalBytes.formattedByteCount)")
						.contentTransition(.numericText())
				}
			}
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding(.vertical, 4)
		.onReceive(download.$progress) { self.progress = $0 }
		.onReceive(download.$bytesDownloaded) { self.bytesDownloaded = $0 }
		.onReceive(download.$totalBytes) { self.totalBytes = $0 }
		.onReceive(download.$unpackageProgress) { self.unpackageProgress = $0 }
	}
	
	private var overallProgress: Double {
		download.onlyArchiving
			? unpackageProgress
			: (0.3 * unpackageProgress) + (0.7 * progress)
	}
}
