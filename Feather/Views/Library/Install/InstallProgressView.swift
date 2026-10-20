//
//  InstallProgressView.swift
//  Feather
//
//  Created by samara on 23.04.2025.
//

import SwiftUI
import IDeviceSwift

struct InstallProgressView: View {
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	
	var body: some View {
		// Accretion: the logo's rings around the app's icon fill as the install goes (outer ring
		// first), and the icon flashes like the logo's star when it's done
		let progress = viewModel.overallProgress
		AccretionOrbitProgress(
			progress: [progress * 3, progress * 3 - 1, progress * 3 - 2].map { min(1, max(0, $0)) },
			done: viewModel.isCompleted,
			size: 150
		) {
			FRAppIconView(app: app, size: 40)
				.frame(width: 40, height: 40)
		}
		.offset(y: -14)
	}
	
	struct PieShape: Shape {
		var progress: Double
		
		func path(in rect: CGRect) -> Path {
			var path = Path()
			let center = CGPoint(x: rect.midX, y: rect.midY)
			let radius = min(rect.width, rect.height) / 2
			let startAngle = Angle(degrees: -90)
			let endAngle = Angle(degrees: -90 + progress * 360)
			
			path.move(to: center)
			path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
			path.closeSubpath()
			
			return path
		}
		
		var animatableData: Double {
			get { progress }
			set { progress = newValue }
		}
	}
}
