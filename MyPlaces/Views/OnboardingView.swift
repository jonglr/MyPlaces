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
    @EnvironmentObject private var userProfileManager: UserProfileManager

    var body: some View {
        VStack {
            Text("Welcome to MyPlacesApp")
                .font(.largeTitle)
                .padding()

            TextField("Enter your name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            TextField("Enter your email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button(action: {
                userProfileManager.createUser(name: name, email: email)
            }) {
                Text("Get Started")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .padding()
    }
}
