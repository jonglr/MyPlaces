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
    @Published var isDarkMode: Bool = false

    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func toggleDark() {
        isDarkMode.toggle()
    }
    
    func switchUser(withID id: UUID) -> UserProfile {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
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
