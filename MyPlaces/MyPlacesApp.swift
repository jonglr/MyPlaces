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
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var settingsManager: SettingsManager
    
    init(){
        ArcGISEnvironment.apiKey = APIKey(Keys.apiKey)
        
        /// Initialize SettingsManager with proper context
        let settingsManager = SettingsManager(context: PersistenceController.shared.container.viewContext)
        self._settingsManager = StateObject(wrappedValue: settingsManager)
    }
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            Group {
                /// Check if a user actually exists in Core Data
                if dataManager.hasUser() {
                    ContentView()
                        .onAppear {
                            /// Ensure SettingsManager has the current user loaded
                            if settingsManager.user == nil {
                                settingsManager.user = dataManager.currentUser()
                            }
                        }
                } else {
                    OnboardingView { user in
                        /// User was successfully created
                        settingsManager.adopt(user: user)
                    }
                }
            }
            .environmentObject(dataManager)
            .environmentObject(settingsManager)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
