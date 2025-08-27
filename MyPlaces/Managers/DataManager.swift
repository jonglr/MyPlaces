//
//  DataManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

///**Class Functions**
/// Handles the saving and retrieval of the Core Data

import CoreData
import SwiftUI

class DataManager: ObservableObject {
    
    @Published var hasUser: Bool = false
    
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    
    // MARK: - User Profile Management
    
    /// Fetch the Current User Profile (Singleton)
    func currentUser() -> UserProfile? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == true")
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching active user profile: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Create a New User Profile
    func createUser(name: String, email: String) {
        let newUser = UserProfile(context: context)
        newUser.userID = UUID()
        newUser.name = name
        newUser.email = email
        newUser.isActive = true
        saveContext()
        hasUser = true
    }
    
    /// Save Theme for the User
    func saveTheme(theme: String) {
        guard let user = currentUser() else {
            print("No valid user found.")
            return
        }
        user.theme = theme
        do {
            try context.save()
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
        }
    }
        
    /// Fetch Theme for the User
    func fetchTheme() -> String? {
        guard let user = currentUser() else {
            print("No valid user found")
            return nil
        }
        return user.theme
    }
    
    
    // MARK: - Relevance Score Management
    
    /// Save a relevance score for a specific POI using its ID
    func saveRelevanceScore(for poiID: UUID, score: Double) {
        guard let user = currentUser() else {
            print("No valid user found to save Relevance Score")
            return
        }
        guard let userID = user.userID else {
            print("User does not have a valid ID to save Relevance Score")
            return
        }

        do {
            // Fetch or create the POI
            let poiFetch: NSFetchRequest<POI> = POI.fetchRequest()
            poiFetch.predicate = NSPredicate(format: "poiID == %@", poiID as CVarArg)
            poiFetch.fetchLimit = 1
            let poi: POI
            
            if let existingPOI = try context.fetch(poiFetch).first {
                poi = existingPOI
            } else {
                /// Create a new POI if it doesn't exist
                poi = POI(context: context)
                poi.poiID = poiID
                poi.favorite = false
                poi.clickCount = 0
                poi.lastClickedDate = nil
                
                /// Save the POI first before establishing relationships
                try context.save()
            }

            /// Fetch existing relevance score
            let fetchRequest: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "poiID == %@ AND userID == %@", poiID as CVarArg, userID as CVarArg)
            fetchRequest.fetchLimit = 1  /// Add fetch limit for efficiency

            let existingScores = try context.fetch(fetchRequest)

            if let existingScore = existingScores.first {
                /// Update existing score
                existingScore.score = score
            } else {
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.score = score
                
                /// Only set relationships if objects are not nil
                if user.managedObjectContext != nil {
                    newScore.user = user
                }
                if poi.managedObjectContext != nil {
                    newScore.poi = poi
                }
            }

            try context.save()
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
            context.rollback()
        }
    }
       
    
    // MARK: - POI Management
    
    func fetchPOI(poiID: UUID, context: NSManagedObjectContext) -> POI? {
        let request: NSFetchRequest<POI> = POI.fetchRequest()
        request.predicate = NSPredicate(format: "poiID == %@", poiID as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching POI details: \(error)")
            return nil
        }
    }
    
    func updatePOIInteraction(poiID: UUID, context: NSManagedObjectContext, isFavorite: Bool? = nil) {
        guard let poi = fetchPOI(poiID: poiID, context: context) else {
            print("POI not found to safe interaction.")
            return
        }
        /// Update favorite status if provided
        if let isFavorite = isFavorite {
            poi.favorite = isFavorite
        }
        /// Update click count and last clicked date
        poi.clickCount += 1
        poi.lastClickedDate = Date()
        
        saveContext()
    }
    
    func getPOIInteraction(poiID: UUID, context: NSManagedObjectContext) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        guard let poi = fetchPOI(poiID: poiID, context: context) else {
            /// If POI not found to retrieve interactions
            print("No interactions with this POI yet.")
            return (false, 0, Calendar.current.date(byAdding: .day, value: -600, to: Date()) ?? Date())
        }
        let fallbackDate = Calendar.current.date(byAdding: .day, value: -600, to: Date()) ?? Date()
        return (poi.favorite, poi.clickCount, poi.lastClickedDate ?? fallbackDate)
    }
    
    
    // MARK: - Context Saving
        
    /// Save Context to CoreData
    func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving to CoreData: \(error.localizedDescription)")
        }
    }
}
