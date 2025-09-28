//
//  UserSwitchView.swift
//  MyPlaces
//
//  Created by Jon Guler on 28.08.2025.
//

/// **Class Functions**
/// The UI View when the user wants to select another profile or delete a profile
/// This file includes several sections and classes:
/// - Avatar Colors: Keep the user profile colors consistant across views
/// - User Switcher View: The main view that gets displayed when the user presses the SwitchUser button on the Panel Overlay which displays all the user profiles with information, avatar display and active status
/// - User Profile Card: The view to select and delete certain user profiles (a modification to the User Switcher View)
/// - Add User (Button): The button in the UserSwitchr Overview which can be pressed and redirects to the AddUser View
/// - Add User View: The View when from the Switcher view, an additional user gets created

import SwiftUI
import CoreData
import CryptoKit


// MARK: - Avatar Colors


/// Shared avatar color utilities (harmonized with the panel overlay when creating and displaying a user profile)
private let avatarColorSets: [[Color]] = [
    [.pink, .red],
    [.orange, .red],
    [.yellow, .orange],
    [.cyan, .blue]
]

private func avatarColors(forID id: String) -> [Color] {
    let digest = SHA256.hash(data: Data(id.utf8))
    let number = digest.withUnsafeBytes { ptr in
        ptr.load(as: UInt64.self) // take first 8 bytes as number
    }
    return avatarColorSets[Int(number % UInt64(avatarColorSets.count))]
}


// MARK: - User Switcher View


struct UserSwitcherView: View {
    @Environment(\.dismiss) var dismiss
    /// Link to the Managers
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var dataManager: DataManager
    
    /// Fetch user profiles
    @FetchRequest(
        entity: UserProfile.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \UserProfile.name, ascending: true)]
    ) var users: FetchedResults<UserProfile>
    
    /// Variable Declaration
    @State private var showingAddUserSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var userToDelete: UserProfile?
    @State private var isEditMode = false
    @State private var showingCannotDeleteAlert = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var usersToDelete: Set<UserProfile> = []
    
    /// View Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    /// Header of the view on top
                    Text("Switch User")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    /// Information text below the header
                    Text("Select a user profile or create a new one")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    /// Edit mode information
                    if isEditMode {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Tap users to select for deletion. Active user cannot be deleted.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    
                    /// Users Grid that hold all the user profiles with the name and avatar pictures
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 20) {
                        ForEach(users) { user in
                            UserProfileCard(
                                user: user,
                                isActive: user.isActive,
                                isEditMode: isEditMode,
                                isSelected: usersToDelete.contains(user),
                                onTap: {
                                    if isEditMode {
                                        toggleUserSelection(user)
                                    } else {
                                        switchToUser(user)
                                    }
                                },
                                onDelete: {
                                    userToDelete = user
                                    showingDeleteConfirmation = true
                                }
                            )
                            .overlay(
                                Group {
                                    if isEditMode && usersToDelete.contains(user) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .red)
                                            .font(.system(size: 24))
                                            .offset(x: 30, y: -30)
                                    }
                                }
                            )
                        }
                        
                        /// Add User Button (only show when not in edit mode)
                        if !isEditMode {
                            AddUserCard {
                                showingAddUserSheet = true
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    
                    /// Bulk delete button for all the selected users
                    if isEditMode && !usersToDelete.isEmpty {
                        Button(action: {
                            showingBulkDeleteConfirmation = true
                        }) {
                            Label("Delete \(usersToDelete.count) User\(usersToDelete.count == 1 ? "" : "s")",
                                  systemImage: "trash")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    Spacer(minLength: 50)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    /// Only show edit if there are multiple users to prevent the system reset to zero users
                    if users.count > 1 {
                        Button(isEditMode ? "Cancel" : "Edit") {
                            withAnimation {
                                isEditMode.toggle()
                                usersToDelete.removeAll()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddUserSheet) {
            AddUserView()
        }
        .alert("Delete User", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let user = userToDelete {
                    deleteUser(user)
                }
            }
        } message: {
            Text("Are you sure you want to delete \(userToDelete?.name ?? "this user")? This will also delete all their data and preferences.")
        }
        .alert("Cannot Delete Active User", isPresented: $showingCannotDeleteAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You cannot delete the currently active user. Please switch to another user first.")
        }
        .alert("Delete \(usersToDelete.count) Users", isPresented: $showingBulkDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                bulkDeleteUsers()
            }
        } message: {
            Text("Are you sure you want to delete \(usersToDelete.count) user\(usersToDelete.count == 1 ? "" : "s")? This action cannot be undone.")
        }
    }
    
    /// Functionality of the Edit View
    private func toggleUserSelection(_ user: UserProfile) {
        if user.isActive {
            /// Can't select active user for deletion
            showingCannotDeleteAlert = true
            return
        }
        
        if usersToDelete.contains(user) {
            usersToDelete.remove(user)
        } else {
            usersToDelete.insert(user)
        }
    }
    
    /// Functionality to delete multiple users that are selected by the active user from the CoreData
    private func bulkDeleteUsers() {
        let context = PersistenceController.shared.container.viewContext
        
        for user in usersToDelete {
            /// Double-check not deleting active user
            if !user.isActive {
                /// Delete associated relevance scores
                if let relevanceScores = user.relevanceScores as? Set<RelevanceScore> {
                    relevanceScores.forEach { context.delete($0) }
                }
                
                /// Delete user
                context.delete(user)
            }
        }
        
        do {
            try context.save()
            usersToDelete.removeAll()
            isEditMode = false
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            print("Error bulk deleting users: \(error)")
        }
    }
    
    /// Functionality to delete a single user profile from Core Data
    private func deleteUser(_ user: UserProfile) {
        guard !user.isActive else {
            showingCannotDeleteAlert = true
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        
        /// Clear user-specific favorites and interactions
        dataManager.clearUserFavorites(for: user)
        dataManager.clearUserInteractions(for: user)  // ADD THIS LINE
        
        /// Delete associated relevance scores
        if let relevanceScores = user.relevanceScores as? Set<RelevanceScore> {
            relevanceScores.forEach { context.delete($0) }
        }
        
        /// Delete user
        context.delete(user)
        
        do {
            try context.save()
            
            /// Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } catch {
            print("Error deleting user: \(error)")
        }
    }
    
    /// When a user profile is tapped, the user gets switched to the tapped profile representation of that certain user
    private func switchToUser(_ user: UserProfile) {
        /// Use the existing switchUser method from SettingsManager
        settingsManager.user = settingsManager.switchUser(withID: user.userID!)
        
        /// Post notification AFTER the user has been switched
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .userDidChange, object: nil)
        }
        /// Dismiss the view
        dismiss()
        
        /// Show confirmation
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}


// MARK: - User Profile Overview


struct UserProfileCard: View {
    let user: UserProfile
    let isActive: Bool
    var isEditMode: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                /// Avatar circle
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 70, height: 70)
                    .opacity(isEditMode && isActive ? 0.5 : 1.0)
                
                Text(user.name?.prefix(1).uppercased() ?? "?")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                
                /// Active indicator
                if isActive && !isEditMode {
                    Circle()
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 76, height: 76)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .background(Circle().fill(Color.white))
                        .offset(x: 25, y: -25)
                }
                
                /// Edit mode: show lock for active user
                if isEditMode && isActive {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .background(Circle().fill(Color.white))
                        .offset(x: 25, y: -25)
                }
                
                /// Selection indicator in edit mode
                if isEditMode && isSelected && !isActive {
                    Circle()
                        .stroke(Color.red, lineWidth: 3)
                        .frame(width: 76, height: 76)
                }
            }
            
            Text(user.name ?? "Unknown")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
            
            if isActive && !isEditMode {
                Text("Active")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
        }
        .frame(width: 100)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .opacity(isEditMode && isActive ? 0.6 : 1.0)
        .onTapGesture {
            if !isEditMode && isActive {
                return /// Don't do anything if tapping active user when not in edit mode
            }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }
        .onLongPressGesture {
            if !isActive && !isEditMode {
                onDelete()
            }
        }
    }
    
    /// Create a gradient our of the predefined colors for safing the user profile (same as in Add User View)
    private var avatarGradient: LinearGradient {
        /// Prefer email, then name, then UUID to ensure stability across launches
        let id = user.email ?? user.name ?? user.userID?.uuidString ?? "default"
        let colors = avatarColors(forID: id)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}


// MARK: - Add User (Button)


struct AddUserCard: View {
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundColor(.gray)
                    .frame(width: 70, height: 70)
                
                Image(systemName: "plus")
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
            }
            
            Text("Add User")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
        .frame(width: 100)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }
    }
}


// MARK: - Add User View


/// The View when from the Switcher view, an additional user gets created
struct AddUserView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    @State private var name = ""
    @State private var email = ""
    @State private var showingEmptyFieldsAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                /// The section to enter the personal details needed to create a unique user Profile
                Section {
                    HStack {
                        Text("Name")
                            .frame(width: 80, alignment: .leading)
                        TextField("Enter name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Email")
                            .frame(width: 80, alignment: .leading)
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                } header: {
                    Text("User Information")
                }
                /// The section below the text fields to enter information and the preview of the user profile avatar
                Section {
                    HStack {
                        Spacer()
                        
                        /// Preview of avatar
                        VStack {
                            ZStack {
                                Circle()
                                    .fill(avatarGradient)
                                    .frame(width: 60, height: 60)
                                
                                Text(name.prefix(1).uppercased())
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            if !name.isEmpty {
                                Text(name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                }
            }
            .navigationTitle("New User")
            .navigationBarTitleDisplayMode(.inline)
            
            /// The toolbar on top to safe or cancel the creation of a new user
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createUser()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || email.isEmpty)
                }
            }
        }
        /// When there is not all the information filled in when creating a new user -> alert raises
        .alert("Missing Information", isPresented: $showingEmptyFieldsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter both name and email to create a new user.")
        }
    }
    
    /// Create a gradient our of the predefined colors for safing the user profile
    private var avatarGradient: LinearGradient {
        /// Use email when available for preview; falls back to name
        let id = !email.isEmpty ? email : (!name.isEmpty ? name : "default")
        let colors = avatarColors(forID: id)
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Functionality of the user creation and integration into the App system
    private func createUser() {
        guard !name.isEmpty && !email.isEmpty else {
            showingEmptyFieldsAlert = true
            return
        }
        
        let context = PersistenceController.shared.container.viewContext
        
        /// Deactivate all current users
        let fetchRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        if let allUsers = try? context.fetch(fetchRequest) {
            allUsers.forEach { $0.isActive = false }
        }
        
        /// Create new user
        let newUser = UserProfile(context: context)
        newUser.userID = UUID()
        newUser.name = name
        newUser.email = email
        newUser.isActive = true
        
        do {
            try context.save()
            
            /// Post notification about user change
            NotificationCenter.default.post(name: .userDidChange, object: nil)
            
            /// Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            dismiss()
        } catch {
            print("Error creating user: \(error)")
        }
    }
}

/// Notification extension to notify the system that the user changed
extension Notification.Name {
    static let userDidChange = Notification.Name("userDidChange")
}
