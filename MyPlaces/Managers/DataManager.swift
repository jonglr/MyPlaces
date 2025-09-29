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
    
    /// Create a New User Profile while Onboarding View
    func createUser(name: String, email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        // First deactivate any existing users (though there shouldn't be any)
        let fetchRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        if let existingUsers = try? context.fetch(fetchRequest) {
            existingUsers.forEach { $0.isActive = false }
        }
        
        /// Create the new user
        let newUser = UserProfile(context: context)
        newUser.userID = UUID()
        newUser.name = name
        newUser.email = email
        newUser.isActive = true
        
        /// Save the context first
        do {
            try context.save()
            /// Now the user is properly saved and can be fetched by currentUser()
            completion(.success(newUser))
        } catch {
            completion(.failure(error))
        }
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
    
    // MARK: - Theme Management
    
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
    
    /// Save Theme which was set by the User
    func setUserTheme(theme: String) {
        guard let user = currentUser() else { print("No valid user found.") ; return }
        user.userTheme = theme
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
    
    /// Save Theme which was predicted for the User
    func setPredictedTheme(theme: String) {
        guard let user = currentUser() else { print("No valid user found.") ; return }
        user.predictedTheme = theme
        do {
            try context.save()
        } catch { print("Error saving theme: \(error.localizedDescription)") }
    }
    
    
    // MARK: - Relevance Score Management
    
    /// Update the existing Relevance Scores, Favorite variable and click data for the user
    func saveRelevanceScore(for poiID: UUID, score: Double, fid: Int64, relevanceData: String? = nil) {
        guard let user = currentUser() else {
            print("No valid user found to save Relevance Score")
            return
        }
        guard let userID = user.userID else {
            print("User does not have a valid ID to save Relevance Score")
            return
        }
        
        do {
            /// Fetch or create the POI
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
                poi.fid = fid
                
                try context.save()
            }
            
            /// Fetch existing relevance score
            let fetchRequest: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "poiID == %@ AND userID == %@",
                poiID as CVarArg,
                userID as CVarArg
            )
            fetchRequest.fetchLimit = 1
            
            let existingScores = try context.fetch(fetchRequest)
            
            if let existingScore = existingScores.first {
                /// Update existing score
                existingScore.score = score
                existingScore.fid = fid
                existingScore.relevanceData = relevanceData
            } else {
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.fid = fid
                newScore.score = score
                newScore.relevanceData = relevanceData
                newScore.isFavorite = false
                newScore.clickCount = 0
                newScore.lastClickedDate = nil
                newScore.user = user
                newScore.poi = poi
            }
            try context.save()
        } catch {
            print("Error saving relevance score: \(error.localizedDescription)")
            context.rollback()
        }
    }
    
    // MARK: - Favorites Management
    
    /// Check if a POI is marked as favorite by the current user
    func isUserFavorite(poiID: UUID) -> Bool {
        guard let user = currentUser(),
              let userID = user.userID else { return false }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(
            format: "userID == %@ AND poiID == %@ AND isFavorite == true",
            userID as CVarArg,
            poiID as CVarArg
        )
        request.fetchLimit = 1
        
        do {
            let count = try context.count(for: request)
            return count > 0
        } catch {
            print("Error checking user favorite: \(error)")
            return false
        }
    }

    /// Set favorite status for a POI for the current user
    func setUserFavorite(poiID: UUID, isFavorite: Bool, fid: Int64) {
        guard let user = currentUser(),
              let userID = user.userID else {
            print("No current user to set favorite")
            return
        }
        
        do {
            /// Ensure the POI exists
            let fid = fid
            let poiFetch: NSFetchRequest<POI> = POI.fetchRequest()
            poiFetch.predicate = NSPredicate(format: "poiID == %@", poiID as CVarArg)
            poiFetch.fetchLimit = 1
            
            let poi: POI
            if let existingPOI = try context.fetch(poiFetch).first {
                poi = existingPOI
            } else {
                /// Create POI if it doesn't exist
                poi = POI(context: context)
                poi.poiID = poiID
            }
            
            /// Handle the user-specific favorite through RelevanceScore
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
                /// Create new RelevanceScore if it doesn't exist
                relevanceScore = RelevanceScore(context: context)
                relevanceScore.userID = userID
                relevanceScore.poiID = poiID
                relevanceScore.fid = fid
                relevanceScore.score = 0.5  // Default neutral score
                relevanceScore.clickCount = 0
                relevanceScore.lastClickedDate = nil
                relevanceScore.user = user
                relevanceScore.poi = poi
            }
            
            /// Set the user-specific favorite flag
            relevanceScore.isFavorite = isFavorite
            
            try context.save()
            
            /// Post notification for UI updates
            NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            
            print("Set favorite status for user \(user.name ?? "Unknown"): POI \(poiID) = \(isFavorite)")
            
        } catch {
            print("Error setting user favorite: \(error)")
        }
    }
    
    /// Get all favorite POIs for current user
    func getUserFavorites() -> [RelevanceScore] {
        guard let user = currentUser(),
              let userID = user.userID else { return [] }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        
        request.predicate = NSPredicate(
            format: "userID == %@ AND isFavorite == true",
            userID as CVarArg
        )
        request.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]
        
        do {
            let favorites = try context.fetch(request)
            print("User \(user.name ?? "?"): Found \(favorites.count) favorites")
            return favorites
        } catch {
            print("Error fetching user favorites: \(error)")
            return []
        }
    }
    
    func getUserFavoriteFIDs() -> [Int64] {
        guard let user = currentUser() else { return [] }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND isFavorite == true",
            user
        )
        
        do {
            let scores = try context.fetch(request)
            return scores.compactMap { $0.fid > 0 ? $0.fid : nil }
        } catch {
            print("Error fetching favorite FIDs: \(error)")
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
    
    /// Update POI interaction (modified to work with user favorites)
    func updatePOIInteraction(poiID: UUID, isFavorite: Bool? = nil, fid: Int64) {
        guard let user = currentUser(),
              let userID = user.userID else {
            print("No current user to update interaction")
            return
        }
        
        do {
            /// Ensure POI exists
            let poiFetch: NSFetchRequest<POI> = POI.fetchRequest()
            poiFetch.predicate = NSPredicate(format: "poiID == %@", poiID as CVarArg)
            poiFetch.fetchLimit = 1
            
            let poi: POI
            if let existingPOI = try context.fetch(poiFetch).first {
                poi = existingPOI
            } else {
                /// Create POI if it doesn't exist
                poi = POI(context: context)
                poi.poiID = poiID
            }
            
            /// Get or create RelevanceScore for this user-POI pair
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
                /// Create new RelevanceScore if it doesn't exist
                relevanceScore = RelevanceScore(context: context)
                relevanceScore.userID = userID
                relevanceScore.poiID = poiID
                relevanceScore.fid = fid
                relevanceScore.score = 0.5  /// Default neutral score
                relevanceScore.clickCount = 0
                relevanceScore.lastClickedDate = nil
                relevanceScore.user = user
                relevanceScore.poi = poi
            }
            
            /// Update user-specific interaction data
            relevanceScore.clickCount += 1
            relevanceScore.lastClickedDate = Date()
            
            try context.save()
            print("Updated interaction for user \(user.name ?? "Unknown"): POI \(poiID), clicks: \(relevanceScore.clickCount)")
            
        } catch {
            print("Error updating POI interaction: \(error)")
            context.rollback()
        }
    }
    
    /// Get the interaction data of a specific POI
    func getPOIInteraction(poiID: UUID) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        guard let user = currentUser() else {
            print("No current user to get interaction")
            return (false, 0, Date.distantPast)
        }
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND poiID == %@",
            user,
            poiID as CVarArg
        )
        request.fetchLimit = 1
        
        do {
            if let relevanceScore = try context.fetch(request).first {
                let lastClicked = relevanceScore.lastClickedDate ?? Date.distantPast
                return (relevanceScore.isFavorite, relevanceScore.clickCount, lastClicked)
            }
        } catch {
            print("Error fetching POI interaction: \(error)")
        }
        
        /// Return defaults if no interaction found
        return (false, 0, Date.distantPast)
    }
    
    /// Clear all interactions of all POIs for a specific user (useful when deleting user)
    func clearUserInteractions(for user: UserProfile) {
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        
        do {
            let scores = try context.fetch(request)
            for score in scores {
                // Reset interaction data
                score.clickCount = 0
                score.lastClickedDate = nil
                score.isFavorite = false
            }
            try context.save()
        } catch {
            print("Error clearing user interactions: \(error)")
        }
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
