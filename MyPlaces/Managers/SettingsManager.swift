//
//  SettingsManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Functions**
/// Manages global user settings in a centralized manner using UserDefaults
/// Includes theme management for the basemap

import Foundation

class SettingsManager: ObservableObject {
    @Published var isDarkMode: Bool = false

    func toggleTheme() {
        isDarkMode.toggle()
    }
}
