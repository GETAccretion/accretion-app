//
//  TabbarView.swift
//  feather
//
//  Created by samara on 23.03.2025.
//

import SwiftUI

struct TabbarView: View {
	@State private var selectedTab: TabEnum = .sources
	@ObservedObject private var _updateManager = UpdateManager.shared

	var body: some View {
		TabView(selection: $selectedTab) {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				TabEnum.view(for: tab)
					.tabItem {
						Label(tab.title, systemImage: tab.icon)
					}
					.tag(tab)
					// Accretion: number of apps with an update waiting (0 hides the badge)
					.badge(tab == .library ? _updateManager.updates.count : 0)
			}
		}
	}
}
