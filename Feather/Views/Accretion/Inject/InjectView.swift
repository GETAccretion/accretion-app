//
//  InjectView.swift
//  Accretion
//

import SwiftUI
import CoreData
import NimbleViews
import UniformTypeIdentifiers

// MARK: - Inject Tweaks
/// Library → ✨ → Inject Tweaks: one screen to put tweaks into a decrypted IPA.
///   1. the app: a decrypted .ipa from Files, or one already in Library
///   2. the tweaks: .deb / .dylib from Files, or from the Accretion tweak library
///   3. a few options (name, install next to the original, ElleKit, remember)
///   4. Sign & Install with your certificate, or Export the modded IPA (unsigned) for another signer
/// App Store copies stay encrypted (FairPlay) and won't run after injection; the screen says so
/// before anything is changed.
struct InjectView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _pipeline = AutoSignPipeline.shared
	@ObservedObject private var _catalog = TweakCatalog.shared

	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .snappy
	) private var _imported: FetchedResults<Imported>

	@State private var _app: Imported?
	@State private var _waitingSince: Date?
	@State private var _importID: String?
	@State private var _importError: String?
	@State private var _tweaks: [URL] = []
	@State private var _name = ""
	@State private var _sideBySide = false
	@State private var _ellekit = true
	@State private var _remember = true
	@State private var _isPickingIPA = false
	@State private var _isPickingTweaks = false
	@State private var _isBrowsingLibrary = false
	@State private var _downloadError: String?

	private var _problems: [Preflight.Problem] {
		guard let app = _app else { return [] }
		var options = OptionsManager.shared.options
		options.signingOption = .onlyModify // app checks only; certificate checks come at signing
		return Preflight.problems(for: app, certificate: nil, options: options)
	}
	private var _isBlocked: Bool { _problems.contains(where: \.isBlocking) }
	private var _canRun: Bool { _app != nil && !_tweaks.isEmpty && !_isBlocked && !_pipeline.isRunning }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 12) {
					Text(verbatim: String.localized("Put tweaks into a decrypted IPA, then sign and install it, or export the modded IPA for another signer."))
						.foregroundStyle(AccretionTheme.muted)
						.fixedSize(horizontal: false, vertical: true)
					_appStep()
					_tweakStep()
					_optionsStep()
					_runStep()
				}
				.padding(16)
			}
			.accretionBackground()
			.navigationTitle(String.localized("Inject Tweaks"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(String.localized("Close")) { _dismiss() }
				}
			}
		}
		.tint(AccretionTheme.accent)
		.task { await _catalog.load() }
		.onChange(of: _imported.count) { _ in _pickNewlyImported() }
		.task(id: _importID) { await _watchImport() }
		.sheet(isPresented: $_isPickingIPA) {
			FileImporterRepresentableView(allowedContentTypes: [.ipa, .tipa], allowsMultipleSelection: false) { urls in
				guard let url = urls.first else { return }
				_waitingSince = Date().addingTimeInterval(-1)
				_importError = nil
				let id = "AccretionInject_\(UUID().uuidString)"
				_importID = id
				let download = DownloadManager.shared.startArchive(from: url, id: id)
				try? DownloadManager.shared.handlePachageFile(url: url, dl: download)
			}
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isPickingTweaks) {
			FileImporterRepresentableView(allowedContentTypes: [.dylib, .deb], allowsMultipleSelection: true) { urls in
				for url in urls {
					FileManager.default.moveAndStore(url, with: "FeatherTweak") { stored in
						if !_tweaks.contains(stored) { _tweaks.append(stored) }
					}
				}
			}
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isBrowsingLibrary) {
			NavigationStack { _libraryPicker() }
		}
	}

	// MARK: 1. App
	private func _appStep() -> some View {
		AccretionSection(String.localized("1 · Decrypted app")) {
			if let app = _app {
				HStack(spacing: 12) {
					FRAppIconView(app: app, size: 48)
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: app.name ?? String.localized("Unknown"))
							.font(.system(size: 15, weight: .semibold))
							.foregroundStyle(AccretionTheme.fg)
						Text(verbatim: [app.identifier, app.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
							.font(.accretionMono(12, weight: .regular))
							.foregroundStyle(AccretionTheme.muted)
							.lineLimit(1)
					}
					Spacer(minLength: 0)
					Button(String.localized("Change")) { _app = nil }
						.buttonStyle(AccretionButtonStyle(prominent: false, ghost: true, compact: true))
				}
				if _problems.isEmpty {
					Label(String.localized("Decrypted: ready for tweaks"), systemImage: "checkmark.seal.fill")
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(AccretionTheme.good)
				}
				ForEach(_problems, id: \.title) { problem in
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: problem.title)
							.font(.system(size: 13, weight: .semibold))
						Text(verbatim: problem.message)
							.font(.system(size: 13))
							.fixedSize(horizontal: false, vertical: true)
					}
					.foregroundStyle(problem.isBlocking ? AccretionTheme.warn : AccretionTheme.muted)
				}
			} else if _waitingSince != nil {
				HStack(spacing: 8) {
					ProgressView()
					Text(verbatim: String.localized("Importing…")).foregroundStyle(AccretionTheme.muted)
				}
			} else {
				if let error = _importError {
					Text(verbatim: error)
						.font(.system(size: 13))
						.foregroundStyle(AccretionTheme.warn)
						.fixedSize(horizontal: false, vertical: true)
				}
				AccretionFlow(spacing: 8) {
					Button(String.localized("Choose IPA from Files")) { _isPickingIPA = true }
						.buttonStyle(AccretionButtonStyle())
					if !_imported.isEmpty {
						Menu {
							ForEach(_imported.prefix(30), id: \.objectID) { app in
								Button(app.name ?? app.identifier ?? String.localized("Unknown")) { _select(app) }
							}
						} label: {
							Text(verbatim: String.localized("From Library"))
						}
						.buttonStyle(AccretionButtonStyle(prominent: false))
					}
				}
			}
		}
	}

	// MARK: 2. Tweaks
	private func _tweakStep() -> some View {
		AccretionSection(String.localized("2 · Tweaks")) {
			if _tweaks.isEmpty {
				Text(verbatim: String.localized("Add .deb or .dylib files. Tweaks that need CydiaSubstrate get ElleKit (option below)."))
					.font(.system(size: 13))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
			}
			ForEach(_tweaks, id: \.self) { tweak in
				HStack(spacing: 10) {
					Image(systemName: tweak.pathExtension == "deb" ? "shippingbox" : "puzzlepiece.extension")
						.foregroundStyle(AccretionTheme.accent)
					Text(verbatim: tweak.lastPathComponent)
						.font(.accretionMono(13, weight: .regular))
						.foregroundStyle(AccretionTheme.fg)
						.lineLimit(1)
						.truncationMode(.middle)
					Spacer(minLength: 0)
					Button {
						_tweaks.removeAll { $0 == tweak }
					} label: {
						Image(systemName: "xmark.circle.fill").foregroundStyle(AccretionTheme.muted)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(String.localized("Remove %@", arguments: tweak.lastPathComponent))
				}
				.padding(.vertical, 8)
				.padding(.horizontal, 10)
				.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
			}
			let suggested = _catalog.suggested(for: _app?.identifier)
			if !suggested.isEmpty {
				Text(verbatim: String.localized("Suggested for this app").uppercased())
					.font(.accretionMono(10.5, weight: .regular))
					.tracking(1)
					.foregroundStyle(AccretionTheme.muted)
					.padding(.top, 4)
				ForEach(suggested) { tweak in _catalogRow(tweak) }
			}
			if let error = _downloadError {
				Text(verbatim: error).font(.system(size: 13)).foregroundStyle(AccretionTheme.warn)
			}
			AccretionFlow(spacing: 8) {
				Button(String.localized("Add from Files")) { _isPickingTweaks = true }
					.buttonStyle(AccretionButtonStyle(prominent: false))
				Button(String.localized("Tweak library")) { _isBrowsingLibrary = true }
					.buttonStyle(AccretionButtonStyle(prominent: false))
			}
			.padding(.top, 2)
		}
	}

	private func _catalogRow(_ tweak: CatalogTweak) -> some View {
		let added = _tweaks.contains { $0.lastPathComponent == tweak.debURL.lastPathComponent }
		return HStack(spacing: 10) {
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: tweak.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(AccretionTheme.fg)
				Text(verbatim: tweak.description)
					.font(.system(size: 12))
					.foregroundStyle(AccretionTheme.muted)
					.lineLimit(2)
			}
			Spacer(minLength: 0)
			if _catalog.downloading.contains(tweak.id) {
				ProgressView()
			} else {
				Button(added ? String.localized("Added") : String.localized("Add")) { _add(tweak) }
					.buttonStyle(AccretionButtonStyle(prominent: false, on: added, compact: true))
					.disabled(added)
			}
		}
	}

	private func _libraryPicker() -> some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 10) {
				if _catalog.tweaks.isEmpty {
					Text(verbatim: _catalog.loadFailed ? String.localized("Couldn't load the tweak library.") : String.localized("Loading…"))
						.foregroundStyle(AccretionTheme.muted)
				}
				ForEach(_catalog.tweaks) { tweak in
					_catalogRow(tweak)
						.padding(12)
						.accretionCard()
				}
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Tweak library"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button(String.localized("Done")) { _isBrowsingLibrary = false }
			}
		}
	}

	// MARK: 3. Options
	private func _optionsStep() -> some View {
		AccretionSection(String.localized("3 · Options")) {
			VStack(alignment: .leading, spacing: 4) {
				Text(verbatim: String.localized("Name on the Home Screen"))
					.font(.accretionMono(10.5, weight: .regular))
					.foregroundStyle(AccretionTheme.muted)
				TextField(_app?.name ?? String.localized("Keep the app's name"), text: $_name)
					.padding(.horizontal, 12)
					.padding(.vertical, 10)
					.background(AccretionTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
					.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
			}
			Toggle(isOn: $_sideBySide) {
				_toggleLabel(String.localized("Install next to the original"), String.localized("Gives the modded copy its own bundle ID. A single-app certificate uses its one slot instead."))
			}
			Toggle(isOn: $_ellekit) {
				_toggleLabel(String.localized("Use ElleKit"), String.localized("Adds the hooking library most tweaks need (in place of CydiaSubstrate)."))
			}
			Toggle(isOn: $_remember) {
				_toggleLabel(String.localized("Remember for updates"), String.localized("Saves these tweaks as the app's recipe, so updates and re-signs keep them."))
			}
		}
		.tint(AccretionTheme.accent)
	}

	private func _toggleLabel(_ title: String, _ detail: String) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: title).font(.system(size: 15, weight: .semibold)).foregroundStyle(AccretionTheme.fg)
			Text(verbatim: detail).font(.system(size: 12)).foregroundStyle(AccretionTheme.muted).fixedSize(horizontal: false, vertical: true)
		}
	}

	// MARK: 4. Run
	private func _runStep() -> some View {
		AccretionSection(String.localized("4 · Build")) {
			AccretionFlow(spacing: 8) {
				Button(String.localized("Sign & Install")) { _run(exportOnly: false) }
					.buttonStyle(AccretionButtonStyle())
					.disabled(!_canRun)
				Button(String.localized("Export modded IPA")) { _run(exportOnly: true) }
					.buttonStyle(AccretionButtonStyle(prominent: false))
					.disabled(!_canRun)
			}
			if let status = _pipeline.status {
				HStack(spacing: 8) {
					ProgressView()
					Text(verbatim: status).font(.footnote).foregroundStyle(AccretionTheme.muted)
				}
			}
			Text(verbatim: String.localized("Export makes an unsigned IPA with the tweaks inside, to sign with any tool. Only use apps you own, and keep mods out of online games."))
				.font(.system(size: 12))
				.foregroundStyle(AccretionTheme.muted)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	// MARK: Actions
	private func _select(_ app: Imported) {
		_app = app
		_waitingSince = nil
		_name = ""
		// start from the app's recipe when it has one, so re-injecting keeps earlier tweaks
		if let recipe = RecipeStore.load(for: app, base: OptionsManager.shared.options) {
			_tweaks = recipe.options.injectionFiles
			_name = recipe.options.appName ?? ""
		}
	}

	/// The import finished (its download entry is gone) without a new app: say so instead of
	/// spinning forever. Gives up waiting after two minutes as well.
	private func _watchImport() async {
		guard let id = _importID else { return }
		for _ in 0..<240 {
			try? await Task.sleep(nanoseconds: 500_000_000)
			if Task.isCancelled || _waitingSince == nil { return }
			if DownloadManager.shared.getDownloadIndex(by: id) == nil {
				try? await Task.sleep(nanoseconds: 1_000_000_000) // let Core Data catch up
				_pickNewlyImported()
				break
			}
		}
		if _waitingSince != nil {
			_waitingSince = nil
			_importError = String.localized("That IPA couldn't be imported. Check that it's a complete .ipa file and try again.")
		}
	}

	private func _pickNewlyImported() {
		guard let since = _waitingSince, let newest = _imported.first, let date = newest.date, date >= since else { return }
		_select(newest)
	}

	private func _add(_ tweak: CatalogTweak) {
		_downloadError = nil
		Task {
			do {
				for file in try await _catalog.download(tweak) where !_tweaks.contains(file) {
					_tweaks.append(file)
				}
			} catch {
				_downloadError = String.localized("Couldn't download %@: %@", arguments: tweak.name, error.localizedDescription)
			}
		}
	}

	private func _run(exportOnly: Bool) {
		guard let app = _app else { return }
		var options = OptionsManager.shared.options
		options.injectionFiles = _tweaks
		options.experiment_replaceSubstrateWithEllekit = _ellekit
		let name = _name.trimmingCharacters(in: .whitespaces)
		options.appName = name.isEmpty ? nil : name
		if _sideBySide, let identifier = app.identifier {
			options.appIdentifier = "\(identifier).accretion"
		}
		_pipeline.inject(app, options: options, remember: _remember, exportOnly: exportOnly)
		_dismiss()
	}
}
