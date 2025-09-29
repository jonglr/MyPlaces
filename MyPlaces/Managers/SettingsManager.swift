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
import CoreData
import SwiftUI

class SettingsManager: ObservableObject {
    @Published var isNightMode: Bool = false
    @Published var user: UserProfile?
    @Published var theme: String = "explore"
    
    private var context: NSManagedObjectContext {
        return PersistenceController.shared.container.viewContext
    }
    
    // MARK: - Initialization
    
    init(context: NSManagedObjectContext) {
        /// Try to load existing user immediately
        self.user = DataManager.shared.currentUser()
        
        /// Load initial theme from CoreData
        let state = DataManager.shared.fetchThemeState()
        self.theme = state.userTheme ?? state.predictedTheme ?? "explore"
        
        /// Listen for theme changes from prediction
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeDidChange,
            object: nil
        )
        /// Listen for user changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserChange),
            name: .userDidChange,
            object: nil
        )
    }
    
    // MARK: - Theme Change Handling
    
    @objc private func handleThemeChange(_ notification: Notification) {
        guard let newTheme = notification.userInfo?["theme"] as? String else { return }
        DispatchQueue.main.async { self.theme = newTheme }
    }
    
    func switchTheme(to newTheme: String) {
        DataManager.shared.setUserTheme(theme: newTheme)
        self.theme = newTheme
        
        NotificationCenter.default.post(
            name: .themeDidChange,
            object: nil,
            userInfo: ["theme": newTheme, "source": "manual"]
        )
        print("User selected theme: \(newTheme)")
    }
    
    // MARK: - User Change Handling
    
    @objc private func handleUserChange(_ notification: Notification) {
        /// Reload the current user when user changes
        DispatchQueue.main.async {
            self.user = DataManager.shared.currentUser()
            
            /// Also reload theme for the new user
            let state = DataManager.shared.fetchThemeState()
            self.theme = state.userTheme ?? state.predictedTheme ?? "explore"
        }
    }
    
    /// Add the user and properly notify observers
    func adopt(user: UserProfile) {
        DispatchQueue.main.async {
            self.user = user
            /// Post notification to ensure all UI updates
            NotificationCenter.default.post(name: .userDidChange, object: nil)
        }
    }
    
    func switchUser(withID id: UUID) -> UserProfile {
        var switchedUser: UserProfile?
        
        context.performAndWait {
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.predicate = NSPredicate(format: "userID == %@", id as CVarArg)
            request.fetchLimit = 1
            
            do {
                /// Deactivate all users
                let allUsers = try context.fetch(UserProfile.fetchRequest())
                allUsers.forEach { $0.isActive = false }
                
                /// Activate the new active user
                if let existingUser = try context.fetch(request).first {
                    existingUser.isActive = true
                    try context.save()
                    
                    switchedUser = existingUser
                }
            } catch {
                print("Failed to switch user: \(error)")
            }
        }
        
        /// Update UI properties outside performAndWait
        if let user = switchedUser {
            self.user = user
            
            /// Load the theme for the new user
            let state = DataManager.shared.fetchThemeState()
            self.theme = state.userTheme ?? state.predictedTheme ?? "explore"
            
            return user
        } else {
            fatalError("Could not activate new user")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
