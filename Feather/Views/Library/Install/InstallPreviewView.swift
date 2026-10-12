//
//  InstallPreview.swift
//  Feather
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?
	
	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = {
			if #available(iOS 26.0, *) {
				28.0
			} else {
				10.5
			}
		}()
		
		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		// Accretion: the store's card surface and border
		.background(AccretionTheme.surface)
		.cornerRadius(cornerRadius)
		.overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(AccretionTheme.line, lineWidth: 1))
		.padding()
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onAppear {
			// Accretion: Fully Local's certificate was withdrawn, so this install moved to another mode
			let defaults = UserDefaults.standard
			let switchedTo = defaults.integer(forKey: "accretion.installModeSwitchedTo")
			guard switchedTo != 0 else { return }
			defaults.removeObject(forKey: "accretion.installModeSwitchedTo")
			UIAlertController.showAlertWithOk(
				title: String.localized("Install mode changed"),
				message: switchedTo == 2
					? String.localized("Fully Local's certificate is no longer accepted by iOS, so installs now use Offline. You can change this in Settings → Installation → Server & SSL.")
					: String.localized("Fully Local's certificate is no longer accepted by iOS, so installs now use Semi Local. For installs without the internet, set up Offline in Settings → Installation → Server & SSL.")
			)
		}
		.onReceive(viewModel.$status) { newStatus in
			if _installationMethod == 0 {
				if case .ready = newStatus {
					// Accretion: iOS won't accept this install's certificate: say so now, with the fix,
					// instead of opening an install iOS will silently refuse
					if installer.getServerMethod() != 1, let check = ServerInstaller.lastCheck, !check.trusted {
						_offerFix(certificateProblem: true)
						return
					}
					// Accretion: if iOS never asks to install, say why instead of waiting forever
					let link = installer.iTunesLink
					DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
						guard case .ready = viewModel.status else { return }
						UIAlertController.showAlertWithCancel(
							title: String.localized("iOS didn't ask to install"),
							message: String.localized("iOS couldn't reach Accretion's local install server. Usually:\n\n• iCloud Private Relay, a VPN or ad-blocking DNS blocks local addresses: turn it off and try again.\n• Or switch Settings → Installation → Server to Semi Local.\n• Or this app uses the same bundle ID as Accretion itself."),
							actions: [
								UIAlertAction(title: String.localized("Try Again"), style: .default) { _ in
									if let url = URL(string: link) { UIApplication.shared.open(url) }
								},
								// one tap to the mode that needs no local DNS (it works where Fully Local is blocked)
								UIAlertAction(title: String.localized("Use Semi Local"), style: .default) { _ in
									UserDefaults.standard.set(1, forKey: "Feather.serverMethod")
									UIAlertController.showAlertWithOk(
										title: String.localized("Switched to Semi Local"),
										message: String.localized("Close this install card and tap Install again. You can switch back in Settings → Installation.")
									)
								},
							]
						)
					}
					// Accretion: Fully Local and Offline serve the manifest themselves; Semi Local opens a page
					if installer.getServerMethod() != 1 {
						UIApplication.shared.open(URL(string: installer.iTunesLink)!)
					} else {
						_isWebviewPresenting = true
					}
				}
				
				if case .sendingPayload = newStatus, installer.getServerMethod() == 1 {
					_isWebviewPresenting = false
				}
				
				if case .installing = newStatus {
					if progressTask == nil {
						progressTask = startInstallProgressPolling(
							bundleID: app.identifier!,
							viewModel: viewModel
						)
					}
				}
				
				// Accretion: feel the result; a server that couldn't start gets its fix offered
				switch newStatus {
				case .completed:
					UINotificationFeedbackGenerator().notificationOccurred(.success)
				case .broken(let error):
					UINotificationFeedbackGenerator().notificationOccurred(.error)
					// only certificate set-up failures; other errors keep their own message
					let certificateError = error is ServerInstaller.InstallCertificateError
						|| String(describing: type(of: error)).contains("NIOSSL")
					if installer.getServerMethod() != 1, certificateError {
						_offerFix(certificateProblem: false)
					}
				default:
					break
				}

				switch newStatus {
				case .completed, .broken(_):
					progressTask?.cancel()
					progressTask = nil
					#if !targetEnvironment(macCatalyst)
					BackgroundAudioManager.shared.stop()
					#endif
				default:
					break
				}
			}
		}
		.onAppear(perform: _install)
		
		#if !targetEnvironment(macCatalyst)
		.onAppear {
			BackgroundAudioManager.shared.start()
		}
		#endif
		
		.onDisappear {
			progressTask?.cancel()
			progressTask = nil
			
			#if !targetEnvironment(macCatalyst)
			BackgroundAudioManager.shared.stop()
			#endif
		}
	}
	
	/// Accretion: the install can't work in the current mode; offer the mode that will, in one tap
	private func _offerFix(certificateProblem: Bool) {
		let offline = installer.getServerMethod() == 2
		let reason: String
		if offline {
			reason = String.localized("Offline installs aren't set up yet: iOS doesn't trust this iPhone's install certificate. Finish Settings → Installation → Server & SSL → Set Up Offline Installs, or use Semi Local now.")
		} else if certificateProblem, ServerInstaller.lastCheck?.revoked == true {
			reason = String.localized("Fully Local's certificate was withdrawn by its issuer, so iOS refuses it. Use Semi Local, or set up Offline installs.")
		} else {
			reason = String.localized("The local install server can't use its certificate, so iOS would refuse this install. Use Semi Local, or check Settings → Installation → Test Install Server.")
		}
		var actions = [
			UIAlertAction(title: String.localized("Use Semi Local"), style: .default) { _ in
				UserDefaults.standard.set(1, forKey: "Feather.serverMethod")
				UIAlertController.showAlertWithOk(
					title: String.localized("Switched to Semi Local"),
					message: String.localized("Close this install card and tap Install again. You can switch back in Settings → Installation.")
				)
			},
		]
		if certificateProblem {
			let link = installer.iTunesLink
			actions.append(UIAlertAction(title: String.localized("Try Anyway"), style: .default) { _ in
				if let url = URL(string: link) { UIApplication.shared.open(url) }
			})
		}
		UIAlertController.showAlertWithCancel(
			title: String.localized("This install won't work yet"),
			message: reason,
			actions: actions
		)
	}

	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update ‘%@‘ with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}
				
		Task.detached {
			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()
				
				let packageUrl = try await handler.archive()
				
				if await !isSharing {
					if await _installationMethod == 0 {
						await MainActor.run {
							installer.packageUrl = packageUrl
							// Accretion: keep a server start-up error instead of showing Ready for a dead server
							if case .broken = viewModel.status { return }
							viewModel.status = .ready
						}
						
						if case .installing = await viewModel.status {
							let task = await startInstallProgressPolling(
								bundleID: app.identifier!,
								viewModel: viewModel
							)

							await MainActor.run {
								progressTask = task
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)
					
					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()
				
				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: InstallErrorText.describe(error), // Accretion: readable reasons

						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}
	
	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = await hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				await MainActor.run {
					viewModel.installProgress = progress
				}

				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 400_000_000) // Accretion: was 1 ms, a busy loop that drained battery
			}
		}
	}

	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
