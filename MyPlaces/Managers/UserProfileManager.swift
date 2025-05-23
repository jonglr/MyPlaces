//
//  UserProfileManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Function**
/// Handles the loading and creation of new User Profiles and stores them locally


import Foundation
import SwiftUI

class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    @Published var currentUser: UserProfile?

    init() {
        loadUserProfile()
    }

    /// Load the Current User Profile
    func loadUserProfile() {
        self.currentUser = DataManager.shared.currentUser()
    }

    /// Create a New User Profile
    func createUser(name: String, email: String) {
        self.currentUser = DataManager.shared.createUser(name: name, email: email)
    }
}
