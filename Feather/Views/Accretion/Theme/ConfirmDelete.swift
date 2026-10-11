//
//  ConfirmDelete.swift
//  Accretion
//

import UIKit

/// "Delete X?" before anything is removed for good (apps, sources, certificates, backups).
/// Swipe and menu deletes in Feather removed things on the first tap.
enum ConfirmDelete {
	static func ask(_ title: String, message: String? = nil, delete: @escaping () -> Void) {
		UIAlertController.showAlertWithCancel(
			title: title,
			message: message,
			actions: [UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in delete() }]
		)
	}
}
