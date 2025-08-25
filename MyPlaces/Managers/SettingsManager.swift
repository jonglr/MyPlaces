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
    
    @Published var theme: String {
        didSet {
            DataManager.shared.saveTheme(theme: theme)
            user.theme = theme
            try? context.save()
            
        }
    }
    
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
        let user = DataManager.shared.currentUser()!
        self.user = user
        self.theme = user.theme ?? "explore" /// default fallback
    }
    
    func switchTheme(to newTheme: String) {
        guard newTheme != self.theme else { return }
        self.theme = newTheme /// triggers didSet
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
}
