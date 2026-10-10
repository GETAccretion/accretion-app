//
//  CertificateProfilesSection.swift
//  Accretion
//

import SwiftUI
import NimbleViews

// MARK: - View
/// Certificate details → Profiles: the main profile plus any extra ones, which app each is
/// assigned to, and a button to add more. One profile per app lets single-App-ID certificates
/// keep several apps installed and update each one in place.
struct CertificateProfilesSection: View {
	let cert: CertificatePair

	@State private var _profiles: [ProfileStore.Profile] = []
	@State private var _assigned: [String: String] = [:]
	@State private var _isImporting = false

	var body: some View {
		NBSection(.localized("Profiles"), secondary: _profiles.count.description) {
			ForEach(_profiles) { profile in
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: _appIDText(profile))
						.font(.subheadline)
					Text(verbatim: _detailText(profile))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.swipeActions(edge: .trailing) {
					if !profile.isMain {
						Button(.localized("Remove"), systemImage: "trash", role: .destructive) {
							ProfileStore.remove(profile, from: cert)
							_reload()
						}
					}
				}
			}
			Button(.localized("Add Profiles"), systemImage: "plus") {
				_isImporting = true
			}
		} footer: {
			Text(.localized("If your seller gives you one profile per app, add them all here. Each app then gets its own profile, so several stay installed and each updates in place. A wildcard profile covers every app on its own."))
		}
		.onAppear(perform: _reload)
		.sheet(isPresented: $_isImporting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.mobileProvision],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					let refused = ProfileStore.add(urls, to: cert)
					_reload()
					if !refused.isEmpty {
						UIAlertController.showAlertWithOk(
							title: String.localized("Some profiles weren't added"),
							message: refused.joined(separator: "\n")
						)
					}
				}
			)
			.ignoresSafeArea()
		}
	}

	private func _reload() {
		_profiles = ProfileStore.profiles(for: cert)
		_assigned = ProfileStore.assignedApps(for: cert)
	}

	private func _appIDText(_ profile: ProfileStore.Profile) -> String {
		switch profile.kind {
		case .wildcard(let prefix): return prefix.isEmpty ? String.localized("Any app (wildcard)") : "\(prefix)*"
		case .explicit(let id): return id
		case nil: return profile.decoded.Name
		}
	}

	private func _detailText(_ profile: ProfileStore.Profile) -> String {
		var parts: [String] = []
		if profile.isMain { parts.append(String.localized("Main")) }
		if let app = _assigned[profile.id] { parts.append(String.localized("Used by %@", arguments: app)) }
		parts.append(String.localized("Expires %@", arguments: profile.decoded.ExpirationDate.formatted(date: .abbreviated, time: .omitted)))
		return parts.joined(separator: " · ")
	}
}
