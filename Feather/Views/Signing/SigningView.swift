//
//  SigningView.swift
//  Feather
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import PhotosUI
import NimbleViews

// MARK: - View
struct SigningView: View {
	@Environment(\.dismiss) var dismiss
	@StateObject private var _optionsManager = OptionsManager.shared
	
	@State private var _temporaryOptions: Options = OptionsManager.shared.options
	@State private var _temporaryCertificate: Int
	@State private var _isAltPickerPresenting = false
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _isSigning = false
	@State private var _selectedPhoto: PhotosPickerItem? = nil
	@State var appIcon: UIImage?
	// Accretion: what the selected certificate's profile allows, and who holds a single-app slot
	@State private var _slotKind: AppIDKind?
	@State private var _slotOccupant: String?
	@State private var _hasOwnSlot = false
	// Accretion: per-app recipe (options, icon, tweaks) re-applied on every re-sign and update
	@State private var _rememberRecipe = true
	@State private var _usingRecipe = false
	// Accretion: sign with the Apple ID (Settings → Apple ID) instead of a certificate; the
	// Settings switch is the default, and the Apple ID is used when there's no certificate
	@State private var _appleIDEmail: String?
	@State private var _useAppleID = UserDefaults.standard.bool(forKey: AppleIDSigning.enabledKey)
	/// The bundle ID change the last certificate fit made, undone when the choice changes
	@State private var _slotFit: SlotFit?
	private struct SlotFit {
		let from: String?
		let to: String
	}
	private var _signsWithAppleID: Bool { _useAppleID && _appleIDEmail != nil }

	/// Accretion: one Keychain read when the screen opens or the sign-in screen closes
	private func _refreshAppleID() {
		_appleIDEmail = AppleIDClient.session?.email
		if certificates.isEmpty, _appleIDEmail != nil { _useAppleID = true }
	}
	
	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>
	
	private func _selectedCert() -> CertificatePair? {
		guard certificates.indices.contains(_temporaryCertificate) else { return nil }
		return certificates[_temporaryCertificate]
	}
	
	var app: AppInfoPresentable
	
	init(app: AppInfoPresentable) {
		self.app = app
		let storedCert = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		__temporaryCertificate = State(initialValue: storedCert)
	}
		
	// MARK: Body
	var body: some View {
		NBNavigationView("", displayMode: .inline) {
			Form {
				_slotNotice()
				_customizationOptions(for: app)
				_cert()
				_customizationProperties(for: app)
				
				// horrible
				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.accretionList() // Accretion: store background
			.overlay {
				VStack(spacing: 0) {
					Spacer()
					NBVariableBlurView()
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
						.rotationEffect(.degrees(180))
						.overlay {
							Button {
								_start()
							} label: {
								NBSheetButton(title: .localized("Start Signing"), style: .prominent)
									.padding()
							}
							.buttonStyle(.plain)
							.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
						}
				}
				.ignoresSafeArea(edges: .bottom)
			}

			.toolbar {
				NBToolbarButton(role: .dismiss)
				ToolbarItem(placement: .principal) {
					Image("Glyph")
						.resizable()
						.scaledToFit()
						.frame(height: 38)
				}
				NBToolbarButton(
					.localized("Reset"),
					style: .text,
					placement: .topBarTrailing
				) {
					_temporaryOptions = OptionsManager.shared.options
					appIcon = nil
					// Accretion: back to defaults, still fitted to the certificate
					_usingRecipe = false
					_applyCertificateSlot()
				}
			}
			.sheet(isPresented: $_isAltPickerPresenting) { SigningAlternativeIconView(app: app, appIcon: $appIcon, isModifing: .constant(true)) }
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.image],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						self.appIcon = UIImage.fromFile(selectedFileURL)?.resizeToSquare()
					}
				)
				.ignoresSafeArea()
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }
				
				Task {
					if let data = try? await newValue.loadTransferable(type: Data.self),
					   let image = UIImage(data: data)?.resizeToSquare() {
						appIcon = image
					}
				}
			}
			.disabled(_isSigning)
			.animation(.smooth, value: _isSigning)
		}
		.onAppear {
			_refreshAppleID() // Accretion
			// Accretion: start from this app's recipe when it has one
			if let recipe = RecipeStore.load(for: app, base: _optionsManager.options) {
				_temporaryOptions = recipe.options
				if let icon = recipe.icon { appIcon = icon }
				_usingRecipe = true
			}

			// ppq protection
			if
				_optionsManager.options.ppqProtection,
				!_signsWithAppleID, // Accretion: the Apple ID adds its team to the ID instead
				let identifier = app.identifier,
				let cert = _selectedCert(),
				cert.ppQCheck
			{
				_temporaryOptions.appIdentifier = "\(identifier).\(_optionsManager.options.ppqString)"
			}
			
			if
				let currentBundleId = app.identifier,
				let newBundleId = _temporaryOptions.identifiers[currentBundleId]
			{
				_temporaryOptions.appIdentifier = newBundleId
			}
			
			if
				let currentName = app.name,
				let newName = _temporaryOptions.displayNames[currentName]
			{
				_temporaryOptions.appName = newName
			}

			_applyCertificateSlot()
		}
		.onChange(of: _temporaryCertificate) { _ in
			_applyCertificateSlot()
		}
		.onChange(of: _useAppleID) { _ in
			_applyCertificateSlot()
		}
	}

	/// Accretion: fit the bundle ID to what the selected certificate's profile allows.
	private func _applyCertificateSlot() {
		// start from the ID as it was before the last fit, so another certificate or the Apple ID
		// doesn't keep a profile's ID
		if let fit = _slotFit, _temporaryOptions.appIdentifier == fit.to {
			_temporaryOptions.appIdentifier = fit.from
		}
		_slotFit = nil
		let cert = _signsWithAppleID ? nil : _selectedCert() // the Apple ID makes its own App IDs
		_slotKind = CertificateSlots.kind(of: cert)
		_slotOccupant = CertificateSlots.occupant(of: cert)?.name
		_hasOwnSlot = false
		// with several profiles, this app gets the profile assigned to it (or a free one)
		if let cert, let key = RecipeStore.key(for: app) ?? app.identifier,
		   ProfileStore.profiles(for: cert).count > 1,
		   let choice = ProfileStore.choose(for: key, cert: cert, assign: false) {
			_slotKind = choice.profile.kind
			_slotOccupant = CertificateSlots.keepsOwnID ? nil : choice.replaces
			_hasOwnSlot = choice.replaces == nil
		}

		guard let original = app.identifier else { return }
		let wanted = _temporaryOptions.appIdentifier ?? original
		let fitted = CertificateSlots.bundleID(wanted, for: _slotKind)
		if fitted != wanted {
			_slotFit = SlotFit(from: _temporaryOptions.appIdentifier, to: fitted)
			_temporaryOptions.appIdentifier = fitted
		}
	}
}

// MARK: - Extension: View
extension SigningView {
	@ViewBuilder
	private func _customizationOptions(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Select Alternative Icon"), systemImage: "app.dashed") { _isAltPickerPresenting = true }
				Button(.localized("Choose from Files"), systemImage: "folder") { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos"), systemImage: "photo") { _isImagePickerPresenting = true }
			} label: {
				if let icon = appIcon {
					Image(uiImage: icon)
						.appIconStyle()
				} else {
					FRAppIconView(app: app, size: 56)
				}
			}
			
			_infoCell(.localized("Name"), desc: _temporaryOptions.appName ?? app.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: _temporaryOptions.appName ?? (app.name ?? ""),
					bindingValue: $_temporaryOptions.appName
				)
			}
			_infoCell(.localized("Identifier"), desc: _temporaryOptions.appIdentifier ?? app.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: _temporaryOptions.appIdentifier ?? (app.identifier ?? ""),
					bindingValue: $_temporaryOptions.appIdentifier
				)
			}
			_infoCell(.localized("Version"), desc: _temporaryOptions.appVersion ?? app.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: _temporaryOptions.appVersion ?? (app.version ?? ""),
					bindingValue: $_temporaryOptions.appVersion
				)
			}
		}
	}
	
	/// Accretion: explain single-app certificates up front instead of failing at install
	@ViewBuilder
	private func _slotNotice() -> some View {
		if case .explicit(let id) = _slotKind {
			Section {
				Label {
					// a saved recipe can still carry the certificate's ID (signed before 1.0.37): then the old text holds
					Text(verbatim: CertificateSlots.keepsOwnID && (_temporaryOptions.appIdentifier ?? app.identifier) != id
						? String.localized("This certificate covers one app ID (%@). The app keeps its own bundle ID, so it installs next to your other apps. Logins shared between apps, notifications and iCloud may not work. To sign every app as %@ instead, change it in Settings → Certificates.", arguments: id, id)
						: _hasOwnSlot
						? String.localized("This app gets its own profile, so it's signed as %@ and installs next to your other apps.", arguments: id)
						: String.localized(
							"This certificate covers one app at a time, so this app is signed as %@ and replaces %@ on your device. Add more profiles in Settings → Certificates to give each app its own slot.",
							arguments: id,
							_slotOccupant ?? String.localized("the last app signed with it")
						))
					.font(.footnote)
				} icon: {
					Image(systemName: "1.circle")
						.foregroundStyle(AccretionTheme.accent2)
				}
			}
			.listRowBackground(AccretionTheme.accent2.opacity(0.12))
		}
	}

	@ViewBuilder
	private func _cert() -> some View {
		NBSection(.localized("Signing")) {
			// Accretion: signed in with an Apple ID (Settings → Apple ID): choose it or a certificate
			if _appleIDEmail != nil {
				Picker(String.localized("Sign With"), selection: $_useAppleID) {
					Text(verbatim: String.localized("Certificate")).tag(false)
					Text(verbatim: String.localized("Apple ID")).tag(true)
				}
			}
			if _signsWithAppleID, let email = _appleIDEmail {
				LabeledContent(String.localized("Apple ID (7 days)")) {
					Text(verbatim: email)
				}
			} else if let cert = _selectedCert() {
				NavigationLink {
					CertificatesView(selectedCert: $_temporaryCertificate).accretionList() // Accretion: store style
				} label: {
					CertificatesCellView(
						cert: cert
					)
				}
			} else if _appleIDEmail == nil {
				// Accretion: no certificate yet: an Apple ID signs apps too (7 days)
				NavigationLink {
					AppleIDView()
						.onDisappear {
							_refreshAppleID()
							_applyCertificateSlot()
						}
				} label: {
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: String.localized("Sign In with Apple ID"))
						Text(verbatim: String.localized("No certificate? Sign apps with your Apple ID for 7 days, or add a certificate in Settings → Certificates."))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			} else {
				Text(.localized("No Certificate"))
					.font(.footnote)
					.foregroundColor(.disabled())
			}

			// Accretion: recipes
			Toggle(isOn: $_rememberRecipe) {
				Label(.localized("Remember for This App"), systemImage: "wand.and.stars")
			}
		} footer: {
			Text(verbatim: _signsWithAppleID
				? String.localized("Signed with your Apple ID's team: the bundle ID gets the team added, extensions are left out, and the app opens for 7 days. Re-sign in Settings → Apple ID.")
				: _usingRecipe
				? String.localized("Using the name, icon, tweaks and properties saved for this app. Tap Reset to start from your defaults.")
				: String.localized("Saves the name, icon, tweaks and properties so updates and re-signs keep them."))
		}
	}
	
	@ViewBuilder
	private func _customizationProperties(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Advanced")) {
			DisclosureGroup(.localized("Modify")) {
				NavigationLink(.localized("Existing Dylibs")) {
					SigningDylibView(
						app: app,
						options: $_temporaryOptions.optional()
					)
					.accretionList()
				}
				
				NavigationLink(.localized("Frameworks & PlugIns")) {
					SigningFrameworksView(
						app: app,
						options: $_temporaryOptions.optional()
					)
					.accretionList()
				}
			
				NavigationLink(.localized("Entitlements") + " (BETA)") {
					SigningEntitlementsView(
						bindingValue: $_temporaryOptions.appEntitlementsFile
					)
					.accretionList()
				}
				
				NavigationLink(.localized("Tweaks")) {
					SigningTweaksView(
						options: $_temporaryOptions,
						appIdentifier: app.identifier // Accretion: tweak suggestions
					)
					.accretionList()
				}
			}
			
			NavigationLink(.localized("Properties")) {
				Form { SigningOptionsView(
					options: $_temporaryOptions,
					temporaryOptions: _optionsManager.options
				)}
				.navigationTitle(.localized("Properties"))
				.accretionList()
			}
		}
	}
	
	@ViewBuilder
	private func _infoCell<V: View>(_ title: String, desc: String?, @ViewBuilder destination: () -> V) -> some View {
		NavigationLink {
			destination().accretionList()
		} label: {
			LabeledContent(title) {
				Text(desc ?? .localized("Unknown"))
			}
		}
	}
}

// MARK: - Extension: View (import)
extension SigningView {
	private func _start() {
		guard
			_selectedCert() != nil || _temporaryOptions.signingOption != .default || _signsWithAppleID // Accretion
		else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		// Accretion: explain problems before signing; blocking ones stop here. Checked against the
		// profile this app will actually be signed with when the certificate has several.
		let cert = _signsWithAppleID ? nil : _selectedCert() // Accretion: Apple ID signing needs no certificate
		_useAppProfile(cert)
		let problems = Preflight.problems(for: app, certificate: cert, options: _temporaryOptions)
		if let cert { ProfileOverride.set(nil, for: cert) }
		Preflight.confirm(problems) {
			_sign()
		}
	}

	/// Accretion: sign with this app's own profile when the certificate has several
	private func _useAppProfile(_ cert: CertificatePair?) {
		if let cert, let key = RecipeStore.key(for: app) ?? app.identifier, ProfileStore.profiles(for: cert).count > 1 {
			ProfileOverride.set(ProfileStore.choose(for: key, cert: cert, assign: true)?.profile.url, for: cert)
		}
	}

	private func _sign() {
		let generator = UIImpactFeedbackGenerator(style: .light)
		generator.impactOccurred()
		_isSigning = true

		let cert = _signsWithAppleID ? nil : _selectedCert() // Accretion: Apple ID signing needs no certificate
		_useAppProfile(cert)

		FR.signPackageFile(
			app,
			using: _temporaryOptions,
			icon: appIcon,
			certificate: cert,
			appleID: _temporaryOptions.signingOption == .default && _signsWithAppleID // Accretion
		) { error in
			ProfileOverride.set(nil, for: cert)
			if let error {
				let ok = UIAlertAction(title: .localized("Dismiss"), style: .cancel) { _ in
					dismiss()
				}
				
				UIAlertController.showAlert(
					title: .localized("Couldn't sign"),
					message: InstallErrorText.describe(error), // Accretion: readable, not the raw error
					actions: [ok]
				)
			} else {
				// Accretion: remember this app's choices (before the imported copy may be deleted)
				if _rememberRecipe {
					RecipeStore.save(options: _temporaryOptions, icon: appIcon, for: app)
				}

				if
					_temporaryOptions.post_deleteAppAfterSigned,
					!app.isSigned
				{
					Storage.shared.deleteApp(for: app)
				}
				
				if _temporaryOptions.post_installAppAfterSigned {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
						NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: nil)
					}
				}
				dismiss()
			}
		}
	}
}
