//
//  PopUpView.swift
//  MyPlaces
//
//  Created by Jon Guler on 24.08.2025.
//

/// **Class Functions**
/// Is responsible for the Pop-Up View when a POI Feature is clicked to shop up with a custom design and the favorite symbol

import SwiftUI
import ArcGIS
import ArcGISToolkit

struct CustomPopupView: View {
    let popup: Popup?
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: ContentViewModel
    @State private var isFavorite: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            /// Custom header placeholderwith favorite button at the top of the Popup
            if let popup = popup,
               let feature = popup.geoElement as? ArcGISFeature {
                customHeader(for: feature)
                    .padding(.horizontal)
                    .padding(.top)
            }
            
            /// Original PopupView Content with the attribute information
            if let popup = popup {
                PopupView(popup: popup, isPresented: $isPresented)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            loadFavoriteStatus()
        }
    }
    
    /// Declaration of the design of the custom header
    private func customHeader(for feature: ArcGISFeature) -> some View {
        HStack {
            /// POI Name
            Text(feature.attributes["name"] as? String ?? "Unknown Place")
                .font(.title.bold())
                .foregroundColor(.primary)
            
            Spacer()
            
            /// Interactive favorite button
            Button(action: {
                toggleFavorite(for: feature)
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .gray)
                    .font(.system(size: 24))
                    .animation(.easeInOut(duration: 0.2), value: isFavorite)
            }
        }
        .padding(.vertical, 8)
    }
    
    /// Dynamic function to make the favorite button react to a tap
    private func toggleFavorite(for feature: ArcGISFeature) {
        guard let fidAny = feature.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return }
        
        let variableManager = VariableManager()
        let poiID = variableManager.uuidFromFID(fid)
        
        // Toggle using the proper user-specific method WITH FID
        DataManager.shared.setUserFavorite(poiID: poiID, isFavorite: !isFavorite, fid: fid)
        isFavorite = !isFavorite  // Update local state
        
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("Toggled favorite for POI \(poiID) with FID \(fid): \(isFavorite)")
    }
    
    /// Retrieve the status of a POI from the CoreData in order to adjust the favorite button accordingly
    private func loadFavoriteStatus() {
        guard let popup = popup,
              let feature = popup.geoElement as? ArcGISFeature,
              let fidAny = feature.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return }
        
        let variableManager = VariableManager()
        let poiID = variableManager.uuidFromFID(fid)
        
        /// Check user-specific favorite status
        isFavorite = DataManager.shared.isUserFavorite(poiID: poiID)
        
        print("Loaded favorite status for POI \(poiID): \(isFavorite)")
    }
}
