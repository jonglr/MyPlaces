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
    @Published var user: UserProfile
    @Published var theme: String = "explore"
    
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        let user = DataManager.shared.currentUser()!
        self.user = user
        
        // Load initial theme from CoreData
        let state = DataManager.shared.fetchThemeState()
        self.theme = state.userTheme ?? state.predictedTheme ?? "explore"
        
        // Listen for theme changes from prediction
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeDidChange,
            object: nil
        )
    }
    @objc private func handleThemeChange(_ notification: Notification) {
        guard let newTheme = notification.userInfo?["theme"] as? String else { return }
        DispatchQueue.main.async { self.theme = newTheme }
    }
    
    func switchTheme(to newTheme: String) {
        DataManager.shared.setUserTheme(theme:newTheme)
        self.theme = newTheme

        NotificationCenter.default.post(
            name: .themeDidChange,
            object: nil,
            userInfo: ["theme": newTheme, "source": "manual"]
        )
        print("User selected theme: \(newTheme)")
    }
    
    func switchUser(withID id: UUID) -> UserProfile {
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
                return existingUser
            } else {
                fatalError("Could not activate new user")
            }
        } catch {
            fatalError("Failed to switch user: \(error)")
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}
