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
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false
    
    init(){
        ArcGISEnvironment.apiKey = APIKey(Keys.apiKey)
        
        /// Initialize DataManager
        let dataManager = DataManager(context: PersistenceController.shared.container.viewContext)
        self._dataManager = StateObject(wrappedValue: dataManager)
        
        /// Initialize SettingsManager with proper context
        let settingsManager = SettingsManager(context: PersistenceController.shared.container.viewContext)
        self._settingsManager = StateObject(wrappedValue: settingsManager)
    }
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            Group{
                if hasOnboarded {
                    ContentView()
                } else {
                    OnboardingView(onUserCreated: { user in
                        settingsManager.adopt(user: user)
                        hasOnboarded = true
                    })
                }
            }
            .environmentObject(dataManager)
            .environmentObject(settingsManager)
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            
        }
    }
}
