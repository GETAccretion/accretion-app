//
//  SigningTweaksView.swift
//  Feather
//
//  Created by samara on 20.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningTweaksView: View {
	@State private var _isAddingPresenting = false
	@ObservedObject private var _catalog = TweakCatalog.shared // Accretion

	@Binding var options: Options
	/// Accretion: the app being signed, to suggest tweaks made for it
	var appIdentifier: String? = nil

	// MARK: Body
	var body: some View {
		NBList(.localized("Tweaks")) {
			_suggested()

			NBSection(.localized("Injection")) {
				SigningOptionsView.picker(
					.localized("Injection Path"),
					systemImage: "doc.badge.gearshape",
					selection: $options.injectPath,
					values: Options.InjectPath.allCases
				)
				SigningOptionsView.picker(
					.localized("Injection Folder"),
					systemImage: "folder.badge.gearshape",
					selection: $options.injectFolder,
					values: Options.InjectFolder.allCases
				)
				
				Toggle(isOn: $options.injectIntoExtensions) {
					Label(.localized("Inject into Extensions"), systemImage: "syringe")
				}
			}
			
			NBSection(.localized("Tweaks")) {
				if !options.injectionFiles.isEmpty {
					ForEach(options.injectionFiles, id: \.absoluteString) { tweak in
						_file(tweak: tweak)
					}
				} else {
					Text(verbatim: .localized("No files chosen."))
						.font(.footnote)
						.foregroundColor(.disabled())
				}
			}
		}
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				_isAddingPresenting = true
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					guard !urls.isEmpty else { return }
					
					for url in urls {
						FileManager.default.moveAndStore(url, with: "FeatherTweak") { url in
							options.injectionFiles.append(url)
						}
					}
				}
			)
			.ignoresSafeArea()
		}
		.animation(.smooth, value: options.injectionFiles)
		.task { await _catalog.load() }
	}
}

// MARK: - Extension: View (Accretion tweak library)
extension SigningTweaksView {
	@ViewBuilder
	private func _suggested() -> some View {
		let suggested = _catalog.suggested(for: appIdentifier)
		if !suggested.isEmpty {
			NBSection(.localized("Suggested for This App")) {
				ForEach(suggested) { tweak in
					TweakRowView(tweak: tweak) {
						if _catalog.downloading.contains(tweak.id) {
							ProgressView()
						} else if TweakCatalog.isAdded(tweak, to: options) {
							Image(systemName: "checkmark.circle.fill")
								.foregroundStyle(.green)
								.accessibilityLabel(.localized("Added"))
						} else {
							Button(.localized("Add")) {
								Task {
									do {
										options.injectionFiles.append(contentsOf: try await _catalog.download(tweak))
									} catch {
										UIAlertController.showAlertWithOk(
											title: String.localized("Couldn't download %@", arguments: tweak.name),
											message: error.localizedDescription
										)
									}
								}
							}
							.buttonStyle(.borderless)
						}
					}
				}
			} footer: {
				Text(.localized("From the Accretion tweak library. Files download from each tweak's own project."))
			}
		}
	}
}

// MARK: - Row
/// One tweak: name, what it does, version, licence and author, with a trailing control.
struct TweakRowView<Trailing: View>: View {
	let tweak: CatalogTweak
	@ViewBuilder var trailing: () -> Trailing

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
				Text(verbatim: tweak.name)
					.font(.headline)
				Text(verbatim: tweak.description)
					.font(.footnote)
					.foregroundStyle(.secondary)
				Text(verbatim: [tweak.version, tweak.license, tweak.author].compactMap { $0 }.joined(separator: " · "))
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			trailing()
		}
	}
}

// MARK: - Extension: View
extension SigningTweaksView {
	@ViewBuilder
	private func _file(tweak: URL) -> some View {
		Label(tweak.lastPathComponent, systemImage: "folder.fill")
			.lineLimit(2)
			.frame(maxWidth: .infinity, alignment: .leading)
			.swipeActions(edge: .trailing, allowsFullSwipe: true) {
				_fileActions(tweak: tweak)
			}
			.contextMenu {
				_fileActions(tweak: tweak)
			}
	}
	
	@ViewBuilder
	private func _fileActions(tweak: URL) -> some View {
		Button(role: .destructive) {
			FileManager.default.deleteStored(tweak) { url in
				if let index = options.injectionFiles.firstIndex(where: { $0 == url }) {
					options.injectionFiles.remove(at: index)
				}
			}
		} label: {
			Label(.localized("Delete"), systemImage: "trash")
		}
	}
}
