//
//  Storage+Certificate.swift
//  Feather
//
//  Created by samara on 16.04.2025.
//

import CoreData
import UIKit.UIImpactFeedbackGenerator
import Zsign

// MARK: - Class extension: certificate
extension Storage {
	func addCertificate(
		uuid: String,
		password: String? = nil,
		nickname: String? = nil,
		ppq: Bool = false,
		expiration: Date,
		isDefault: Bool = false,
		completion: @escaping (Error?) -> Void
	) {
		let generator = UIImpactFeedbackGenerator(style: .light)

		// Accretion: the selection is an index into the newest-first list, and the new certificate
		// goes in at index 0, so move the selection along to keep the same certificate selected
		if !getAllCertificates().isEmpty {
			let selected = UserDefaults.standard.integer(forKey: "feather.selectedCert")
			UserDefaults.standard.set(selected + 1, forKey: "feather.selectedCert")
		}

		let new = CertificatePair(context: context)
		new.uuid = uuid
		new.date = Date()
		new.password = password
		new.ppQCheck = ppq
		new.expiration = expiration
		new.nickname = nickname
		new.isDefault = isDefault
		Storage.shared.revokagedCertificate(for: new)
		saveContext()
		generator.impactOccurred()
		completion(nil)
	}
	
	func deleteCertificate(for cert: CertificatePair) {
		// Accretion: keep the same certificate selected when one before it in the list goes away
		if let index = getAllCertificates().firstIndex(of: cert) {
			let selected = UserDefaults.standard.integer(forKey: "feather.selectedCert")
			if index < selected {
				UserDefaults.standard.set(selected - 1, forKey: "feather.selectedCert")
			} else if index == selected {
				UserDefaults.standard.set(0, forKey: "feather.selectedCert")
			}
		}

		if let url = getUuidDirectory(for: cert) {
			try? FileManager.default.removeItem(at: url)
		}
		context.delete(cert)
		saveContext()
	}
	
	func getCertificate(for index: Int) -> CertificatePair? {
		let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]

		guard
			let results = try? context.fetch(fetchRequest),
			index >= 0 && index < results.count
		else {
			return nil
		}
		
		return results[index]
	}
	
	func revokagedCertificate(for cert: CertificatePair) {
		guard !cert.revoked else { return }
		
		Zsign.checkRevokage(
			provisionPath: Storage.shared.getFile(.provision, from: cert)?.path ?? "",
			p12Path: Storage.shared.getFile(.certificate, from: cert)?.path ?? "",
			p12Password: cert.password ?? ""
		) { (status, _, _) in
			if status == 1 {
				DispatchQueue.main.async {
					cert.revoked = true
					self.saveContext()
				}
			}
		}
	}
	
	enum FileRequest: String {
		case certificate = "p12"
		case provision = "mobileprovision"
	}
	
	func getFile(_ type: FileRequest, from cert: CertificatePair) -> URL? {
		guard let url = getUuidDirectory(for: cert) else {
			return nil
		}
		
		return FileManager.default.getPath(in: url, for: type.rawValue)
	}
	
	func getProvisionFileDecoded(for cert: CertificatePair) -> Certificate? {
		guard let url = getFile(.provision, from: cert) else {
			return nil
		}
		
		let read = CertificateReader(url)
		return read.decoded
	}
	
	func getUuidDirectory(for cert: CertificatePair) -> URL? {
		guard let uuid = cert.uuid else {
			return nil
		}
		
		return FileManager.default.certificates(uuid)
	}
	
	func getAllCertificates() -> [CertificatePair] {
		let fetchRequest: NSFetchRequest<CertificatePair> = CertificatePair.fetchRequest()
		fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
		return (try? context.fetch(fetchRequest)) ?? []
	}
}
