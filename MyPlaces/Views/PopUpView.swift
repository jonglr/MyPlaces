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
            // Custom header with favorite button
            if let popup = popup,
               let feature = popup.geoElement as? ArcGISFeature {
                customHeader(for: feature)
                    .padding(.horizontal)
                    .padding(.top)
                
            }
            
            // Original PopupView
            if let popup = popup {
                PopupView(popup: popup, isPresented: $isPresented)
                    .padding(.horizontal)
            }
        }
        .onAppear {
            loadFavoriteStatus()
        }
    }
    
    private func customHeader(for feature: ArcGISFeature) -> some View {
        HStack {
            // POI Name
            Text(feature.attributes["name"] as? String ?? "Unknown Place")
                .font(.title.bold())
                .foregroundColor(.primary)
            
            Spacer()
            
            // Favorite button
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
    
    private func toggleFavorite(for feature: ArcGISFeature) {
        guard let fidAny = feature.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return }
        
        let variableManager = VariableManager()
        let poiID = variableManager.uuidFromFID(fid)
        
        // Update favorite status
        isFavorite.toggle()
        
        // Update in Core Data
        let context = PersistenceController.shared.container.viewContext
        DataManager.shared.updatePOIInteraction(
            poiID: poiID,
            context: context,
            isFavorite: isFavorite
        )
        
        // Trigger haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func loadFavoriteStatus() {
        guard let popup = popup,
              let feature = popup.geoElement as? ArcGISFeature,
              let fidAny = feature.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return }
        
        let variableManager = VariableManager()
        let poiID = variableManager.uuidFromFID(fid)
        
        let context = PersistenceController.shared.container.viewContext
        let (favorite, _, _) = DataManager.shared.getPOIInteraction(
            poiID: poiID,
            context: context
        )
        
        isFavorite = favorite
    }
}
