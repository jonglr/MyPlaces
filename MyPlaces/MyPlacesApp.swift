//
//  MyPlacesApp.swift
//  MyPlaces
//
//  Created by Jon Guler on 27.01.2025.
//

/// **Class Functions**
/// Entry point for the App

import SwiftUI
import ArcGIS
import CoreData


@main
struct MyPlacesApp: App {
    
    let persistenceController = PersistenceController.shared
    @StateObject private var dataManager: DataManager
    @StateObject private var settingsManager: SettingsManager
    
    init(){
        ArcGISEnvironment.apiKey = APIKey(Keys.apiKey)
        
        // Initialize DataManager first
        let dataManager = DataManager(context: PersistenceController.shared.container.viewContext)
        self._dataManager = StateObject(wrappedValue: dataManager)
        
        // Then SettingsManager with proper context
        let settingsManager = SettingsManager(context: PersistenceController.shared.container.viewContext)
        self._settingsManager = StateObject(wrappedValue: settingsManager)
    }
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            if dataManager.hasUser {
                ContentView()
                    .environmentObject(dataManager)
                    .environmentObject(settingsManager)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            } else {
                OnboardingView()
                    .environmentObject(dataManager)
            }
        }
    }
}
