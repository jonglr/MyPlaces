//
//  PanelOverlay.swift
//  MyPlaces
//
//  Created by Jon Guler on 27.08.2025.
//

/// **Class Functions**
/// Shows the saved favorites of a user in the UI and handles the user Switching and Profile


import SwiftUI
import CoreData
import ArcGIS
import CryptoKit

struct FavoritesPanel: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var dataManager: DataManager
    @ObservedObject var viewModel: ContentViewModel
    
    @State private var dragOffset: CGFloat = 0
    @State private var panelHeight: CGFloat = 180 /// Collapsed height
    @State private var isExpanded: Bool = false
    @State private var favoritePOIs: [FavoritePOI] = []
    @State private var showingUserSwitcher = false
    
    let collapsedHeight: CGFloat = 180
    let expandedHeight: CGFloat = 600
    let minDragThreshold: CGFloat = 50
    
    
    struct FavoritePOI: Identifiable {
        let id = UUID()
        let poiID: UUID
        let name: String
        let fclass: String
        let feature: ArcGISFeature
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            dragIndicator
            
            // Header with user profile
            headerSection
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            // Favorites list
            if isExpanded {
                favoritesListSection
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // Show horizontal scroll when collapsed
                horizontalFavoritesSection
                    .transition(.opacity)
            }
            
            Spacer(minLength: 0)
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: -5)
        .offset(y: dragOffset)
        .gesture(dragGesture)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: panelHeight)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        // IMPORTANT: All listeners should be at the top level
        .onAppear {
            loadFavorites()
            // Also try loading after a short delay to ensure POIs are loaded
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
                loadFavorites()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
            print("Favorites changed notification received")
            loadFavorites()
        }
        .onReceive(NotificationCenter.default.publisher(for: .userDidChange)) { _ in
            print("User changed notification received")
            // Clear current favorites immediately
            favoritePOIs = []
            // Load new user's favorites
            loadFavorites()
            
            // Also reload after a delay to ensure data is ready
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                loadFavorites()
            }
        }
        .onChange(of: settingsManager.user?.userID) {
            print("User ID changed in settings")
            // Clear and reload when user changes
            favoritePOIs = []
            loadFavorites()
        }
    }
    
    private var dragIndicator: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
    
    private var headerSection: some View {
        HStack {
            Text("My Favorites")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            // User profile button
            profileButton
        }
    }
    
    private var profileButton: some View {
        Menu {
            Section {
                Label(settingsManager.user?.name ?? "User", systemImage: "person.fill")
                Label(settingsManager.user?.email ?? "", systemImage: "envelope.fill")
            }
            
            Divider()
            
            Button(action: {
                showingUserSwitcher = true
            }) {
                Label("Switch User", systemImage: "person.2.fill")
            }
            
            Button(action: {
                // Add settings logic here if needed
            }) {
                Label("Settings", systemImage: "gear")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 40, height: 40)
                
                Text(settingsManager.user?.name?.prefix(1).uppercased() ?? "U")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showingUserSwitcher) {
            UserSwitcherView()
                .environmentObject(settingsManager)
                .environmentObject(dataManager)
        }
    }
    
    private var avatarGradient: LinearGradient {
        let id = settingsManager.user?.email ?? settingsManager.user?.name ?? "default"
        let digest = SHA256.hash(data: Data(id.utf8))
        let number = digest.withUnsafeBytes { ptr in
            return ptr.load(as: UInt64.self) /// take first 8 bytes as number
        }
        let colorSets: [[Color]] = [
            [.pink, .red],
            [.orange, .red],
            [.yellow, .orange],
            [.cyan, .blue]
        ]
        let colors = colorSets[Int(number % UInt64(colorSets.count))]
        
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var horizontalFavoritesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if favoritePOIs.isEmpty {
                    Text("No favorites yet")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(favoritePOIs) { favorite in
                        favoriteCard(for: favorite)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    private var favoritesListSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                if favoritePOIs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "star.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No favorites yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap the star icon on any place to save it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(favoritePOIs) { favorite in
                        favoriteListItem(for: favorite)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }
    
    private func favoriteCard(for favorite: FavoritePOI) -> some View {
        Button(action: {
            navigateToPOI(favorite.feature)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: iconForFclass(favorite.fclass))
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                    Spacer()
                }
                
                Text(favorite.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 100, height: 70)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func favoriteListItem(for favorite: FavoritePOI) -> some View {
        Button(action: {
            navigateToPOI(favorite.feature)
        }) {
            HStack {
                Image(systemName: iconForFclass(favorite.fclass))
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(favorite.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(favorite.fclass.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                withAnimation(.interactiveSpring()) {
                    if value.translation.height < -minDragThreshold && !isExpanded {
                        // Swipe up - expand
                        isExpanded = true
                        panelHeight = expandedHeight
                    } else if value.translation.height > minDragThreshold && isExpanded {
                        // Swipe down - collapse
                        isExpanded = false
                        panelHeight = collapsedHeight
                    }
                    dragOffset = 0
                }
            }
    }
    
    private func loadFavorites() {
        // Get current user's favorites with FIDs
        let userFavoriteScores = dataManager.getUserFavorites()
        print("Found \(userFavoriteScores.count) favorite scores for current user")
        
        // First, ensure remote favorites are loaded
        Task {
            await viewModel.loadFavoritePOIsByFID()
            
            await MainActor.run {
                // Now build the favorites list
                var favorites: [FavoritePOI] = []
                
                for score in userFavoriteScores {
                    guard let poiID = score.poiID else { continue }
                    
                    // Try to find by FID first (more reliable)
                    let feature: ArcGISFeature?
                    if score.fid > 0 {
                        feature = viewModel.findPOIByFID(score.fid)
                    } else {
                        // Fallback to UUID search for old data
                        feature = findFeatureForPOI(poiID: poiID)
                    }
                    
                    if let feature = feature {
                        let name = feature.attributes["name"] as? String ?? "Unknown"
                        let fclass = feature.attributes["fclass"] as? String ?? ""
                        
                        favorites.append(FavoritePOI(
                            poiID: poiID,
                            name: name,
                            fclass: fclass,
                            feature: feature
                        ))
                    } else {
                        print("Could not find favorite with FID \(score.fid) or UUID \(poiID)")
                    }
                }
                
                self.favoritePOIs = favorites.sorted { $0.name < $1.name }
                print("Displayed \(favoritePOIs.count) of \(userFavoriteScores.count) favorites")
            }
        }
    }
    
    private func findFeatureForPOI(poiID: UUID) -> ArcGISFeature? {
        let variableManager = VariableManager()
        
        // First search through displayed POIs
        for feature in viewModel.displayedPOIs {
            if let fidAny = feature.attributes["fid"],
               let fid = (fidAny as? NSNumber)?.int64Value {
                let featurePoiID = variableManager.uuidFromFID(fid)
                if featurePoiID == poiID {
                    return feature
                }
            }
        }
        
        // If not found in displayed, search through all POIs
        // This ensures we can navigate to favorites that aren't currently displayed
        if let poiModel = viewModel.poiModel {
            for feature in poiModel.POIs {
                if let fidAny = feature.attributes["fid"],
                   let fid = (fidAny as? NSNumber)?.int64Value {
                    let featurePoiID = variableManager.uuidFromFID(fid)
                    if featurePoiID == poiID {
                        return feature
                    }
                }
            }
        }
        
        return nil
    }
    
    private func navigateToPOI(_ feature: ArcGISFeature) {
        // Notify ContentView to navigate to this POI
        NotificationCenter.default.post(
            name: .navigateToPOI,
            object: nil,
            userInfo: ["feature": feature]
        )
        
        // Collapse panel after selection
        withAnimation {
            isExpanded = false
            panelHeight = collapsedHeight
        }
    }
    
    private func iconForFclass(_ fclass: String) -> String {
        switch fclass {
        case "restaurant", "cafe", "bar", "fast_food":
            return "fork.knife"
        case "hotel", "hostel", "motel":
            return "bed.double.fill"
        case "museum", "theatre", "cinema":
            return "building.columns.fill"
        case "park", "beach", "viewpoint":
            return "leaf.fill"
        case "supermarket", "mall", "shop":
            return "cart.fill"
        case "bus_stop", "railway_station":
            return "bus.fill"
        default:
            return "mappin.circle.fill"
        }
    }
}

// Notification extensions
extension Notification.Name {
    static let favoritesDidChange = Notification.Name("favoritesDidChange")
    static let navigateToPOI = Notification.Name("navigateToPOI")
}
