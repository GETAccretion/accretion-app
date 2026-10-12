//
//  ServerView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleJSON
import NimbleViews

// MARK: - Extension: Model
extension ServerView {
	struct ServerPackModel: Decodable {
		var cert: String
		var ca: String
		var key: String
		var info: ServerPackInfo
		
		private enum CodingKeys: String, CodingKey {
			case cert, ca, key1, key2, info
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			cert = try container.decode(String.self, forKey: .cert)
			ca = try container.decode(String.self, forKey: .ca)
			let key1 = try container.decode(String.self, forKey: .key1)
			let key2 = try container.decode(String.self, forKey: .key2)
			key = key1 + key2
			info = try container.decode(ServerPackInfo.self, forKey: .info)
		}
		
		struct ServerPackInfo: Decodable {
			var issuer: Domains
			var domains: Domains
		}
		
		struct Domains: Decodable {
			var commonName: String
			
			private enum CodingKeys: String, CodingKey {
				case commonName = "commonName"
			}
		}
	}
}

// MARK: - View
struct ServerView: View {
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1
	// Accretion: the recommended modes first (tags are the stored values: 0 Fully Local, 1 Semi Local, 2 Offline)
	private struct _Method: Identifiable { let id: Int; let name: String }
	private let _serverMethods: [_Method] = [
		_Method(id: 1, name: String.localized("Semi Local")),
		_Method(id: 2, name: String.localized("Offline")),
		_Method(id: 0, name: String.localized("Fully Local (backloop.dev)")),
	]
	
	private let _dataService = NBFetchService()
	private let _serverPackUrl = "https://backloop.dev/pack.json"
	
	// MARK: Body
	var body: some View {
		Group {
			Section {
				Picker(.localized("Server Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods) { method in
						Text(method.name).tag(method.id)
					}
				}
				// Accretion: the pop-up menu glitches on iOS 26 inside this list; rows with a checkmark don't
				.pickerStyle(.inline)
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}
			
			// Accretion: what each mode needs
			Section {
				switch _serverMethod {
				case 2:
					NavigationLink {
						OfflineInstallSetupView().accretionList()
					} label: {
						Label(String.localized("Set Up Offline Installs"), systemImage: "lock.shield")
					}
				default:
					EmptyView()
				}
			} footer: {
				switch _serverMethod {
				case 2:
					Text(String.localized("Installs work without the internet, using a certificate made on this iPhone. Needs a one-time setup."))
				case 0:
					Text(String.localized("Uses backloop.dev's public certificate. If iOS no longer accepts it, installs switch to another mode automatically."))
				default:
					Text(String.localized("Recommended. The app is served from this iPhone; Accretion's server only provides the small install manifest. Needs the internet."))
				}
			}
			
			Section {
				// Accretion: check the install server step by step on this network
				NavigationLink {
					InstallServerTestView().accretionList()
				} label: {
					Label(String.localized("Test Install Server"), systemImage: "stethoscope")
				}
				Button(.localized("Update SSL Certificates"), systemImage: "arrow.down.doc") {
					FR.downloadSSLCertificates(from: _serverPackUrl) { success in
						if success {
							DispatchQueue.main.async {
								UIAlertController.showAlertWithOk(
									title: .localized("SSL Certificates"),
									message: .localized("Certificates updated successfully.")
								)
							}
						} else {
							DispatchQueue.main.async {
								UIAlertController.showAlertWithOk(
									title: .localized("SSL Certificates"),
									message: .localized("Failed to download, check your internet connection and try again.")
								)
							}
						}
					}
				}
			}
		}
	}
}
