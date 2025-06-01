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
        try! context.save()
        print("Theme saved successfully: \(theme)")
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
        let poiFetch: NSFetchRequest<POI> = POI.fetchRequest()
        poiFetch.predicate = NSPredicate(format: "id == %@", poiID as CVarArg)
        poiFetch.fetchLimit = 1
        
        do {
            guard let poi = try context.fetch(poiFetch).first else {
                print("No POI found for Saving the Relevance Score with ID: \(poiID)")
                return
            }
            
            // Fetch any existing relevance score
            let fetchRequest: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "poiID == %@ AND user.id == %@", poiID as CVarArg, userID as CVarArg)
            
            let existingScores = try context.fetch(fetchRequest)
            
            if let existingScore = existingScores.first {
                // Update
                existingScore.score = score
            } else {
                // Create
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.score = score
                newScore.user = user
                newScore.poi = poi
            }
            
            try! context.save()
            print("Relevance score saved for POI \(poiID) and User \(userID).")
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
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
    
    func getPOIInteraction(poiID: UUID, context: NSManagedObjectContext) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        guard let poi = fetchPOI(poiID: poiID, context: context) else {
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
