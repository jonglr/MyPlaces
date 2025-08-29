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
    
    /// Fetch the Current User Profile
    func currentUser() -> UserProfile? {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == true")
        request.fetchLimit = 1
        
        do {
            let user = try context.fetch(request).first
            return user
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
    }
    
    /// Checks if there is a user in the database
    func hasUser() -> Bool {
        let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking if user exists: \(error)")
            return false
        }
    }
    
    /// Save Theme which was set by the User
    func setUserTheme(theme: String) {
        guard let user = currentUser() else { print("No valid user found.") ; return }
        user.userTheme = theme
        do {
            try context.save()
        } catch { print("Error saving theme: \(error.localizedDescription)") }
    }
    
    /// Save Theme which was predicted for the User
    func setPredictedTheme(theme: String) {
        guard let user = currentUser() else { print("No valid user found.") ; return }
        user.predictedTheme = theme
        do {
            try context.save()
        } catch { print("Error saving theme: \(error.localizedDescription)") }
    }
    
    /// Clear the userTheme variable in Core Data during a location change
    func clearUserTheme() {
        guard let user = currentUser() else { print("No valid user found.") ; return }
        user.userTheme = nil
        do {
            try context.save()
        } catch { print("Error saving theme: \(error.localizedDescription)") }
    }
        
    struct ThemeState {
        let userTheme: String?
        let predictedTheme: String?
    }

    /// Return the two theme attributes
    func fetchThemeState() -> ThemeState {
        let user = currentUser()
        return ThemeState(
            userTheme: user?.userTheme,
            predictedTheme: user?.predictedTheme
        )
    }
    
    
    // MARK: - Relevance Score Management
    
    /// Update the existing saveRelevanceScore to preserve favorite status
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
                // DON'T reset favorite status for existing POIs
            } else {
                // Create a new POI if it doesn't exist
                poi = POI(context: context)
                poi.poiID = poiID
                poi.favorite = false
                poi.clickCount = 0
                poi.lastClickedDate = nil
                
                try context.save()
            }
            
            // Fetch existing relevance score
            let fetchRequest: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "poiID == %@ AND userID == %@",
                poiID as CVarArg,
                userID as CVarArg
            )
            fetchRequest.fetchLimit = 1
            
            let existingScores = try context.fetch(fetchRequest)
            
            if let existingScore = existingScores.first {
                // Update existing score but PRESERVE favorite status
                existingScore.score = score
                // Don't change existingScore.isFavorite - preserve it!
            } else {
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.score = score
                newScore.isFavorite = false  // New scores default to not favorite
                newScore.user = user
                newScore.poi = poi
            }
            
            try context.save()
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
            context.rollback()
        }
    }
    
    // MARK: - User-Specific Favorites Management
    
    /// Check if a POI is marked as favorite by the current user
    func isUserFavorite(poiID: UUID) -> Bool {
        guard let user = currentUser() else { return false }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND poiID == %@ AND isFavorite == true",
            user,
            poiID as CVarArg
        )
        request.fetchLimit = 1
        
        do {
            return try context.count(for: request) > 0
        } catch {
            print("Error checking user favorite: \(error)")
            return false
        }
    }
    
    /// Set favorite status for a POI for the current user
    func setUserFavorite(poiID: UUID, isFavorite: Bool) {
        guard let user = currentUser(),
              let userID = user.userID else {
            print("No current user to set favorite")
            return
        }
        
        do {
            // First, ensure the POI exists
            let poiFetch: NSFetchRequest<POI> = POI.fetchRequest()
            poiFetch.predicate = NSPredicate(format: "poiID == %@", poiID as CVarArg)
            poiFetch.fetchLimit = 1
            
            let poi: POI
            if let existingPOI = try context.fetch(poiFetch).first {
                poi = existingPOI
            } else {
                // Create POI if it doesn't exist
                poi = POI(context: context)
                poi.poiID = poiID
                poi.clickCount = 0
                poi.lastClickedDate = nil
                poi.favorite = false  // Global favorite stays false
            }
            
            // Now handle the user-specific favorite through RelevanceScore
            let scoreFetch: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            scoreFetch.predicate = NSPredicate(
                format: "user == %@ AND poiID == %@",
                user,
                poiID as CVarArg
            )
            scoreFetch.fetchLimit = 1
            
            let relevanceScore: RelevanceScore
            if let existingScore = try context.fetch(scoreFetch).first {
                relevanceScore = existingScore
            } else {
                // Create new RelevanceScore if it doesn't exist
                relevanceScore = RelevanceScore(context: context)
                relevanceScore.userID = userID
                relevanceScore.poiID = poiID
                relevanceScore.user = user
                relevanceScore.poi = poi
                relevanceScore.score = 0.5  // Default neutral score
            }
            
            // Set the user-specific favorite flag
            relevanceScore.isFavorite = isFavorite
            
            // If marking as favorite, boost the relevance score
            if isFavorite && relevanceScore.score < 0.8 {
                relevanceScore.score = 0.8  // Boost score for favorites
            }
            
            try context.save()
            
            // Post notification for UI updates
            NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            
            print("Set favorite status for user \(user.name ?? "Unknown"): POI \(poiID) = \(isFavorite)")
            
        } catch {
            print("Error setting user favorite: \(error)")
        }
    }
    
    /// Toggle favorite status for current user
    func toggleUserFavorite(poiID: UUID) -> Bool {
        let currentStatus = isUserFavorite(poiID: poiID)
        setUserFavorite(poiID: poiID, isFavorite: !currentStatus)
        return !currentStatus
    }
    
    /// Get all favorite POIs for current user
    func getUserFavorites() -> [RelevanceScore] {
        guard let user = currentUser() else { return [] }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND isFavorite == true",
            user
        )
        request.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching user favorites: \(error)")
            return []
        }
    }
    
    /// Clear all favorites for a user (useful when deleting user)
    func clearUserFavorites(for user: UserProfile) {
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        
        do {
            let scores = try context.fetch(request)
            for score in scores {
                score.isFavorite = false
            }
            try context.save()
        } catch {
            print("Error clearing user favorites: \(error)")
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
    
    /// Update POI interaction (modified to work with user favorites)
    func updatePOIInteraction(poiID: UUID, context: NSManagedObjectContext, isFavorite: Bool? = nil) {
        guard let poi = fetchPOI(poiID: poiID, context: context) else {
            // If POI doesn't exist, create it
            let newPOI = POI(context: context)
            newPOI.poiID = poiID
            newPOI.clickCount = 1
            newPOI.lastClickedDate = Date()
            newPOI.favorite = false
            
            saveContext()
            
            // Handle favorite if specified
            if let isFavorite = isFavorite {
                setUserFavorite(poiID: poiID, isFavorite: isFavorite)
            }
            return
        }
        
        // Update click count and last clicked date
        poi.clickCount += 1
        poi.lastClickedDate = Date()
        
        // Handle favorite status through user-specific method
        if let isFavorite = isFavorite {
            setUserFavorite(poiID: poiID, isFavorite: isFavorite)
        }
        
        saveContext()
    }
    
    func getPOIInteraction(poiID: UUID, context: NSManagedObjectContext) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        guard let poi = fetchPOI(poiID: poiID, context: context) else {
            /// If POI not found to retrieve interactions
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
