//
//  LoadingOverlay.swift
//  MyPlaces
//
//  Created by Jon Guler on 26.08.2025.
//
import SwiftUI

struct LoadingOverlay: View {
    let text: String?

    var body: some View {
        ZStack {
            /// Centered spinner + label
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                if let text {
                    Text(text)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 10)
        }
        /// Block taps while visible
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(text ?? "Loading"))
    }
}

struct LoadingOverlayModifier: ViewModifier {
    @Binding var isPresented: Bool
    var text: String?

    func body(content: Content) -> some View {
        content
            .disabled(isPresented) // prevent interaction
            .overlay(
                Group {
                    if isPresented {
                        LoadingOverlay(text: text)
                            .transition(.opacity.combined(with: .scale))
                            .animation(.easeInOut(duration: 0.2), value: isPresented)
                    }
                }
            )
    }
}

extension View {
    func loadingOverlay(isPresented: Binding<Bool>, text: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isPresented: isPresented, text: text))
    }
}
