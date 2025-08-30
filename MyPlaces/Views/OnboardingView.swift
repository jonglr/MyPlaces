//
//  OnboardingView.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Function**
/// Presents itself to the user such that a new user profile can get created

import SwiftUI

struct OnboardingView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    @EnvironmentObject var dataManager: DataManager
    let onUserCreated: (UserProfile) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("Welcome to MyPlaces")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
            
            Text("Let's get you started")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                TextField("Enter your name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                TextField("Enter your email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding(.horizontal)
            }
            .padding(.vertical)

            Button(action: createUser) {
                Text("Get Started")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(name.isEmpty || email.isEmpty)
            .opacity(name.isEmpty || email.isEmpty ? 0.6 : 1.0)
            
            Spacer()
            Spacer()
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func createUser() {
        dataManager.createUser(name: name, email: email) { result in
            switch result {
            case .success(let user):
                onUserCreated(user)
            case .failure(let error):
                errorMessage = "Failed to create user: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
