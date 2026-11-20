//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	#if !NIGHTLY && !DEBUG
		@AppStorage("Feather.shouldStar") private var _shouldStar: Int = 0
	#endif
	@StateObject var viewModel = SourcesViewModel.shared
	@ObservedObject private var _store = StoreService.shared // Accretion: the store's sources
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	
	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Sources")) {
			NBListAdaptable {
				if !_filteredSources.isEmpty {
					Section {
						NavigationLink {
							SourceAppsView(object: Array(_sources), viewModel: viewModel)
						} label: {
							let isRegular = horizontalSizeClass != .compact
							HStack(spacing: 18) {
								Image("Repositories").appIconStyle()
								NBTitleWithSubtitleView(
									title: .localized("All Repositories"),
									subtitle: .localized("See all apps from your sources")
								)
							}
							.padding(isRegular ? 12 : 0)
							.background(
								isRegular
									? RoundedRectangle(cornerRadius: 18, style: .continuous)
									.fill(Color(.quaternarySystemFill))
									: nil
							)
						}
						.buttonStyle(.plain)
					}

					AccretionShelfView(viewModel: viewModel)

					NBSection(
						.localized("Repositories"),
						secondary: _filteredSources.count.description
					) {
						ForEach(_filteredSources) { source in
							NavigationLink {
								SourceAppsView(object: [source], viewModel: viewModel)
							} label: {
								SourcesCellView(source: source)
							}
							.buttonStyle(.plain)
						}
					}
					
					// Accretion: the sources the store merges, in the same list as yours
					if let count = _store.index?.sources.count, _searchText.isEmpty {
						NBSection(.localized("Accretion Store")) {
							NavigationLink(value: StoreSourcesRoute()) {
								NBTitleWithSubtitleView(
									title: String.localized("Store Sources"),
									subtitle: String.localized("The %@ public sources merged into Discover", arguments: count.formatted())
								)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.accretionList() // Accretion: store background
			.searchable(text: $_searchText, placement: .platform())
			.overlay {
				if _filteredSources.isEmpty {
					if #available(iOS 17, *) {
						ContentUnavailableView {
							Label(.localized("No Repositories"), systemImage: "globe.desk.fill")
						} description: {
							Text(.localized("Get started by adding your first repository."))
						} actions: {
							Button {
								_isAddingPresenting = true
							} label: {
								NBButton(.localized("Add Source"), style: .text)
							}
							// Accretion: the store's sources are here too
							NavigationLink(value: StoreSourcesRoute()) {
								NBButton(.localized("Browse Store Sources"), style: .text)
							}
						}
					} else {
						// Accretion: iOS 16
						AccretionEmptyState(title: String.localized("No Sources"), message: String.localized("Get started by adding your first source."), systemImage: "globe.desk.fill") {
							Button(String.localized("Add Source")) { _isAddingPresenting = true }
								.buttonStyle(AccretionButtonStyle())
							NavigationLink(value: StoreSourcesRoute()) { Text(verbatim: String.localized("Browse Store Sources")) }
								.buttonStyle(AccretionButtonStyle(prominent: false))
						}
					}
				}
			}
			.toolbar {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing,
					isDisabled: _addingSourceLoading
				) {
					_isAddingPresenting = true
				}
			}
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
			}
			.accretionStoreDestinations() // Accretion: store sources open store pages
			.task { await StoreService.shared.load() }
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
		#if !NIGHTLY && !DEBUG
		.onAppear {
				guard _shouldStar < 6 else { return }; _shouldStar += 1
				guard _shouldStar == 6 else { return }
			
				let github = UIAlertAction(title: "GitHub", style: .default) { _ in
					UIApplication.open("https://github.com/GETAccretion/accretion-app")
				}
			
				let cancel = UIAlertAction(title: .localized("Dismiss"), style: .cancel)
			
				UIAlertController.showAlert(
					title: .localized("Enjoying %@?", arguments: Bundle.main.name),
					message: .localized("Go to our GitHub and give us a star!"),
					actions: [github, cancel]
				)
			}
		#endif
	}
}
