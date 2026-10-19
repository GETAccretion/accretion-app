//
//  InstallServerTestView.swift
//  Accretion
//

import SwiftUI

struct InstallServerTestView: View {
	@State private var _checks: [InstallServerProbe.Check] = []
	@State private var _running = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 12) {
				Text(verbatim: String.localized("Checks the local server installs use, step by step, on this network."))
					.foregroundStyle(AccretionTheme.muted)
					.fixedSize(horizontal: false, vertical: true)
				Button {
					_running = true
					_checks = []
					Task {
						_checks = await InstallServerProbe.run()
						_running = false
					}
				} label: {
					Text(verbatim: _running ? String.localized("Testing…") : String.localized("Run Test")).frame(maxWidth: .infinity)
				}
				.buttonStyle(AccretionButtonStyle())
				.disabled(_running)

				ForEach(_checks) { check in
					HStack(alignment: .top, spacing: 12) {
						Image(systemName: check.state == .pass ? "checkmark.circle.fill" : check.state == .warn ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
							.foregroundStyle(check.state == .pass ? AccretionTheme.good : AccretionTheme.warn)
							.accretionFont(18)
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: check.title).accretionFont(15, weight: .semibold).foregroundStyle(AccretionTheme.fg)
							Text(verbatim: check.detail).accretionFont(13).foregroundStyle(AccretionTheme.muted).fixedSize(horizontal: false, vertical: true)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
					.accretionCard()
					.accessibilityElement(children: .combine)
				}
				if !_running, !_checks.isEmpty, !_checks.contains(where: { $0.state != .pass }) {
					Text(verbatim: String.localized("Everything works. If an install still doesn't start, iOS refused that app: check its bundle ID and certificate."))
						.accretionFont(13)
						.foregroundStyle(AccretionTheme.good)
						.fixedSize(horizontal: false, vertical: true)
				}
			}
			.padding(16)
		}
		.accretionBackground()
		.navigationTitle(String.localized("Test Install Server"))
		.navigationBarTitleDisplayMode(.inline)
	}
}
