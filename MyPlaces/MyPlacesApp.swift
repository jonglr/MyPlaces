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
    @StateObject private var userProfileManager = UserProfileManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var dataManager = DataManager(context: PersistenceController.shared.container.viewContext)
    
    init(){
        ArcGISEnvironment.apiKey = APIKey(Keys.apiKey)
    }
    
    var body: some SwiftUI.Scene {
        WindowGroup {
            /// if there is no user profile stored yet, the Onboarding view will be shown to the user
            if userProfileManager.currentUser == nil {
                OnboardingView()
                    .environmentObject(userProfileManager)
            } else {
                ContentView()
                    .environmentObject(settingsManager)
                    .environmentObject(dataManager)
                    .environmentObject(userProfileManager)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            }
        }
    }
}
