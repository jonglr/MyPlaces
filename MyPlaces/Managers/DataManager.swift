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
    
    static let shared = DataManager()
    private let persistentContainer = PersistenceController.shared.container
    
    private init() {
    }
    
    private var context: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    
    // MARK: - User Profile Management
    
    /// Create a New User Profile while Onboarding View
    func createUser(name: String, email: String, completion: @escaping (Result<UserProfile, Error>) -> Void) {
        performAndSave { context in
            /// First deactivate any existing users
            let fetchRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            let existingUsers = try context.fetch(fetchRequest)
            existingUsers.forEach { $0.isActive = false }
            
            /// Create the new user
            let newUser = UserProfile(context: context)
            newUser.userID = UUID()
            newUser.name = name
            newUser.email = email
            newUser.isActive = true
            
            /// Save
            completion(.success(newUser))
        }
    }
    
    /// Checks if there is a user in the database
    func hasUser() -> Bool {
        var hasUser = false
        context.performAndWait {
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.fetchLimit = 1
            
            do {
                let count = try context.count(for: request)
                hasUser = count > 0
            } catch {
                print("Error checking if user exists: \(error)")
            }
        }
        return hasUser
    }
    
    /// Fetch the Current User Profile
    func currentUser() -> UserProfile? {
        var user: UserProfile?
        context.performAndWait {
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == true")
            request.fetchLimit = 1
            
            do {
                user = try context.fetch(request).first
            } catch {
                print("Error fetching active user profile: \(error.localizedDescription)")
            }
        }
        return user
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
        performAndSave { context in
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == true")
            guard let user = try context.fetch(request).first else {
                print("No valid user found.")
                return
            }
            user.userTheme = theme
        }
    }
    
    /// Clear the userTheme variable in Core Data during a location change
    func clearUserTheme() {
        performAndSave { context in
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == true")
            guard let user = try context.fetch(request).first else {
                print("No valid user found.")
                return
            }
            user.userTheme = nil
        }
    }
    
    /// Save Theme which was predicted for the User
    func setPredictedTheme(theme: String) {
        performAndSave { context in
            let request: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == true")
            guard let user = try context.fetch(request).first else {
                print("No valid user found.")
                return
            }
            user.predictedTheme = theme
        }
    }
    
    
    // MARK: - Relevance Score Management
    
    /// Update the existing Relevance Scores, Favorite variable and click data for the user
    func saveRelevanceScore(for poiID: UUID, score: Double, fid: Int64, relevanceData: String? = nil) {
        performAndSave { context in
            /// Get current user within the context
            let userRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            userRequest.predicate = NSPredicate(format: "isActive == true")
            userRequest.fetchLimit = 1
            
            guard let user = try context.fetch(userRequest).first,
                  let userID = user.userID else {
                print("No valid user found to save Relevance Score")
                return
            }
            
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
                existingScore.poi = poi
                existingScore.user = user
                existingScore.relevanceData = relevanceData
            } else {
                /// Create new score
                let newScore = RelevanceScore(context: context)
                newScore.userID = userID
                newScore.poiID = poiID
                newScore.fid = fid
                newScore.score = score
                newScore.poi = poi
                newScore.user = user
                newScore.isFavorite = false
                newScore.clickCount = 0
                newScore.lastClickedDate = nil
                newScore.relevanceData = relevanceData
            }
        }
    }
    
    // MARK: - Favorites Management
    
    /// Check if a POI is marked as favorite by the current user
    func isUserFavorite(poiID: UUID) -> Bool {
        var isFavorite = false
        context.performAndWait {
            guard let user = currentUser(),
                  let userID = user.userID else { return }
            
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(
                format: "userID == %@ AND poiID == %@ AND isFavorite == true",
                userID as CVarArg,
                poiID as CVarArg
            )
            request.fetchLimit = 1
            
            do {
                let count = try context.count(for: request)
                isFavorite = count > 0
            } catch {
                print("Error checking user favorite: \(error)")
            }
        }
        return isFavorite
    }

    /// Set favorite status for a POI for the current user
    func setUserFavorite(poiID: UUID, isFavorite: Bool, fid: Int64) {
        performAndSave { context in
            /// Get user within context
            let userRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            userRequest.predicate = NSPredicate(format: "isActive == true")
            guard let user = try context.fetch(userRequest).first,
                  let userID = user.userID else {
                print("No current user to set favorite")
                return
            }
            
            /// Ensure the POI exists
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
                poi.fid = fid
            }
            
            /// Handle the user-specific favorite through RelevanceScore
            let scoreFetch: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            scoreFetch.predicate = NSPredicate(
                format: "userID == %@ AND poiID == %@",
                userID as CVarArg,
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
            
            /// Set the user-specific favorite flag
            relevanceScore.isFavorite = isFavorite
            
            /// Post notification for UI updates
            NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            
            print("Set favorite status for user \(user.name ?? "Unknown"): POI \(poiID) = \(isFavorite)")
        }
    }
    
    /// Get all favorite POIs for current user
    func getUserFavorites() -> [RelevanceScore] {
        var favorites: [RelevanceScore] = []
        context.performAndWait {
            guard let user = currentUser(),
                  let userID = user.userID else { return }
            
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(
                format: "userID == %@ AND isFavorite == true",
                userID as CVarArg
            )
            request.sortDescriptors = [NSSortDescriptor(key: "score", ascending: false)]
            
            do {
                favorites = try context.fetch(request)
                print("User \(user.name ?? "?"): Found \(favorites.count) favorites")
            } catch {
                print("Error fetching user favorites: \(error)")
            }
        }
        return favorites
    }
    
    func getUserFavoriteFIDs() -> [Int64] {
        var fids: [Int64] = []
        context.performAndWait {
            guard let user = currentUser() else { return }
            
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND isFavorite == true",
                user
            )
            
            do {
                let scores = try context.fetch(request)
                fids = scores.compactMap { $0.fid > 0 ? $0.fid : nil }
            } catch {
                print("Error fetching favorite FIDs: \(error)")
            }
        }
        return fids
    }
    
    /// Clear all favorites for a user (useful when deleting user)
    func clearUserFavorites(for user: UserProfile) {
        performAndSave { context in
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@", user)
            
            let scores = try context.fetch(request)
            for score in scores {
                score.isFavorite = false
            }
        }
    }
       
    
    // MARK: - POI Management
    
    /// Update POI interaction
    func updatePOIInteraction(poiID: UUID, isFavorite: Bool? = nil, fid: Int64, clickIncrement: Bool = false) {
        performAndSave { context in
            /// Get user within context
            let userRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
            userRequest.predicate = NSPredicate(format: "isActive == true")
            guard let user = try context.fetch(userRequest).first,
                  let userID = user.userID else {
                print("No current user to update interaction")
                return
            }
            
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
                poi.fid = fid
            }
            
            /// Get or create RelevanceScore for this user-POI pair
            let scoreFetch: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            scoreFetch.predicate = NSPredicate(
                format: "userID == %@ AND poiID == %@",
                userID as CVarArg,
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
            if clickIncrement {
                relevanceScore.clickCount += 1
                relevanceScore.lastClickedDate = Date()
            }
            
            if let favoriteStatus = isFavorite {
                relevanceScore.isFavorite = favoriteStatus
            }
            
            print("Updated interaction for user \(user.name ?? "Unknown"): POI \(poiID), clicks: \(relevanceScore.clickCount)")
        }
    }
    
    /// Get the interaction data of a specific POI
    func getPOIInteraction(poiID: UUID, context: NSManagedObjectContext? = nil) -> (isFavorite: Bool, clickCount: Int32, lastClickedDate: Date) {
        var result: (Bool, Int32, Date) = (false, 0, Date.distantPast)
        
        let contextToUse = context ?? self.context
        contextToUse.performAndWait {
            guard let user = currentUser() else {
                print("No current user to get interaction")
                return
            }
            
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(
                format: "user == %@ AND poiID == %@",
                user,
                poiID as CVarArg
            )
            request.fetchLimit = 1
            
            do {
                if let relevanceScore = try contextToUse.fetch(request).first {
                    let lastClicked = relevanceScore.lastClickedDate ?? Date.distantPast
                    result = (relevanceScore.isFavorite, relevanceScore.clickCount, lastClicked)
                }
            } catch {
                print("Error fetching POI interaction: \(error)")
            }
        }
        return result
    }
    
    /// Clear all interactions of all POIs for a specific user
    func clearUserInteractions(for user: UserProfile) {
        performAndSave { context in
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(format: "user == %@", user)
            
            let scores = try context.fetch(request)
            for score in scores {
                /// Reset interaction data
                score.clickCount = 0
                score.lastClickedDate = nil
                score.isFavorite = false
            }
        }
    }
    
    
    // MARK: - Context Saving
    
    /// Thread-safe wrapper for Core Data operations
    private func performAndSave(_ block: @escaping (NSManagedObjectContext) throws -> Void) {
        let context = persistentContainer.viewContext
        context.performAndWait {
            do {
                try block(context)
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                print("Core Data error: \(error)")
                context.rollback()
            }
        }
    }
    
    func performBackgroundBatchUpdate(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask { backgroundContext in
            backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            block(backgroundContext)
            
            if backgroundContext.hasChanges {
                do {
                    try backgroundContext.save()
                } catch {
                    print("Background save error: \(error)")
                }
            }
        }
    }
}
