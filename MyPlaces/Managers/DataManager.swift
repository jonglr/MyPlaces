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
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    
    // MARK: - User Profile Management
    
    /// Fetch the Current User Profile (Singleton)
    func currentUser() -> UserProfile? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching current user profile: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Create a New User Profile
    func createUser(name: String, email: String) -> UserProfile? {
        let newUser = UserProfile(context: context)
        newUser.userID = UUID()
        newUser.name = name
        newUser.email = email
        
        saveContext()
        return newUser
    }
    
    /// Save Theme for the User
    func saveTheme(theme: String) {
        guard let user = currentUser() else {
            print("No valid user found.")
            return
        }
        
        user.theme = theme
        saveContext()
        print("Theme saved successfully: \(theme)")
    }
        
    /// Fetch Theme for the User
    func fetchTheme() -> String? {
        guard let user = currentUser() else {
            print("No valid user found.")
            return nil
        }
        return user.theme
    }
    
    
    // MARK: - Relevance Score Management
    
    /// Save a relevance score for a specific POI using its ID
    func saveRelevanceScore(for poiID: UUID, userID: UUID, score: Double) {
        let context = self.context
        let fetchRequest: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "poiID == %@ AND user.id == %@", poiID as CVarArg, userID as CVarArg)
        
        do {
            /// Fetch existing score if it exists
            let existingScores = try context.fetch(fetchRequest)
            if let existingScore = existingScores.first {
                existingScore.score = score
            } else {
                /// Create a new score if none exists
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.score = score
            }
            /// Save context
            saveContext()
            print("Relevance score saved successfully.")
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
        }
    }
       
    
    // MARK: - POI Management
    
    func fetchPOIDetails(poiID: UUID, context: NSManagedObjectContext) -> POI? {
        let request: NSFetchRequest<POI> = POI.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", poiID as CVarArg)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Error fetching POI details: \(error)")
            return nil
        }
    }
    
    func updatePOIInteraction(poiID: UUID, context: NSManagedObjectContext, isFavorite: Bool? = nil) {
        guard let poi = fetchPOIDetails(poiID: poiID, context: context) else {
            print("POI not found.")
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
    
    func getPOIInteractionDetails(poiID: UUID, context: NSManagedObjectContext) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        guard let poi = fetchPOIDetails(poiID: poiID, context: context) else {
            print("POI not found.")
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
