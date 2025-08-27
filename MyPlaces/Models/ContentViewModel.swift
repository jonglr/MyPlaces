//
//  ContentViewModel.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Functions**
/// Manages user interactions with the MapView.
/// Calculates and updates relevance scores

import SwiftUI
import CoreData
import ArcGIS

class ContentViewModel: ObservableObject {
    
    /// The POI Model is initialized asynchronously
    private var poiModel: POIModel?
    /// stores all the POIs temporarely, before the relevant ones get published in order to get displayed
    private var allPOIs: [ArcGISFeature] = []
    /// The visualization of the relevant POIs that get overlayed onto the rest of the POIs
    @Published var displayedPOIs: [ArcGISFeature] = []
    /// Exposed flag to display the loading sign in the view model
    @Published var isComputingRelevance = false
    
    /// Core Data Managers
    private let context = PersistenceController.shared.container.viewContext
    private let dataManager = DataManager.shared
    
    /// Generate Managers
    private let variableManager = VariableManager()
    private let relevanceModelManager = RelevanceModelManager()
    private let thematicModelManager = ThematicModelManager()
    
    /// Search Attributes
    let graphicsOverlay = GraphicsOverlay()
    let locator = LocatorTask(
        url: URL(string: "https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer")!
    )

    // MARK: - Theme Mapping Helper
    
    /// Looks up the corresponding fclasses that match the thematic map choice
    private lazy var themeMappings: [String: [Double]] = {
        guard let url = Bundle.main.url(forResource: "theme_mappings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mappings = json["themeMappings"] as? [String: [String: Any]] else {
            print("Failed to load theme mappings")
            return [:]
        }
        
        var result: [String: [Double]] = [:]
        for (themeId, themeData) in mappings {
            if let fclasses = themeData["fclasses"] as? [Double] {
                result[themeId] = fclasses
            }
        }
        return result
    }()

    private func getFclassesForTheme(_ theme: Double) -> [Double] {
        let themeKey = String(Int(theme))
        return themeMappings[themeKey] ?? []
    }
    
    
    // MARK: - Initialization
    
    /// Asynchronous Loading and calculation of the relevant of POIs
    init() {
        Task {
            await updateTheme()
            await initializePOIModel()
            await updateRelevance()
            await loadRelevanceScores()
        }
    }
    
    /// Async Initialization of the POIModel
    @MainActor
    private func initializePOIModel() async {
        let model = await POIModel(variableManager: variableManager) // Initialize asynchronously
        await MainActor.run {
            self.poiModel = model
            self.allPOIs = model.POIs
        }
    }
    
    /// Load Relevance Scores and Filter POIs
    @MainActor
    func loadRelevanceScores() async {
        await MainActor.run {
            guard dataManager.currentUser() != nil else {
                print("No user logged in.")
                return
            }
            guard let allPOIs = poiModel?.POIs else {
                print("POI model not initialized")
                return
            }
            
            /// Get current user theme
            let currentTheme = variableManager.currentUserTheme()
            let themeClasses = getFclassesForTheme(currentTheme)
            
            /// Filter POIs that have relevance scores > 0.5
            let relevantPOIs = allPOIs.compactMap { poi -> (poi: ArcGISFeature, score: Double, fclass: Double)? in
                let score = getRelevanceScore(for: poi)
                guard score > 0.5 else { return nil }
                
                /// Get fclass for thematic filtering
                guard let fclassRaw = poi.attributes["fclass"] as? String,
                      let fclass = variableManager.fclassConversion(fclass: fclassRaw) else {
                    return nil
                }
                
                return (poi: poi, score: score, fclass: fclass)
            }
            print("Filtered POIs before thematic filtering: \(relevantPOIs.count)")
            
            /// Separate POIs into themed (match user map theme) and non-themed groups
            let themedPOIs = relevantPOIs.filter { themeClasses.isEmpty || themeClasses.contains($0.fclass) }
            let nonThemedPOIs = relevantPOIs.filter { !themeClasses.isEmpty && !themeClasses.contains($0.fclass) }
            
            /// Sort both groups by relevance score (highest first)
            let sortedThemedPOIs = themedPOIs.sorted { $0.score > $1.score }
            let sortedNonThemedPOIs = nonThemedPOIs.sorted { $0.score > $1.score }
            
            /// Calculate balanced counts - use themed POI count as the limit
            let availableThemedCount = sortedThemedPOIs.count
            let availableDiscoveryCount = sortedNonThemedPOIs.count
            
            /// Take all available themed POIs
            let selectedThemedPOIs = sortedThemedPOIs
            
            /// Take same number of discovery POIs as themed POIs (or all if fewer available)
            let discoveryTargetCount = min(availableThemedCount, availableDiscoveryCount)
            let selectedDiscoveryPOIs = Array(sortedNonThemedPOIs.prefix(discoveryTargetCount))
            
            /// Combine all selected POIs
            let combinedPOIs = (selectedThemedPOIs + selectedDiscoveryPOIs).map { $0.poi }
            
            print("Themed POIs: \(selectedThemedPOIs.count), Discovery POIs: \(selectedDiscoveryPOIs.count)")
            print("Total POIs before aggregation: \(combinedPOIs.count)")
            
            /// Apply aggregation to remove overlapping POIs with the threshold of X meters
            let filteredGeneralizedPOIs = filterOverlappingPOIs(pois: combinedPOIs, threshold: 25)
            print("Filtered POIs after aggregation: \(filteredGeneralizedPOIs.count)")
            
            /// Update displayed POIs
            self.displayedPOIs = filteredGeneralizedPOIs
            
            print("All POIs: \(allPOIs.count) Loaded Relevant POIs: \(displayedPOIs.count)")
            print("Current theme: \(currentTheme) (\(getThemeName(currentTheme)))")
        }
    }
    
    /// Helper function to get theme name for logging
    private func getThemeName(_ theme: Double) -> String {
        let themeKey = String(Int(theme))
        guard let url = Bundle.main.url(forResource: "theme_mappings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mappings = json["themeMappings"] as? [String: [String: Any]],
              let themeData = mappings[themeKey],
              let name = themeData["name"] as? String else {
            return "Unknown"
        }
        return name
    }
    
    /// Helper function to get relevance score for a POI
    func getRelevanceScore(for poi: ArcGISFeature) -> Double {
        guard let user = dataManager.currentUser(),
              let fidAny = poi.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return 0.0 }
        
        let poiID = variableManager.uuidFromFID(fid)
        
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND poiID == %@", user, poiID as CVarArg)
        
        do {
            let scores = try context.fetch(request)
            return scores.first?.score ?? 0.0
        } catch {
            print("Error fetching relevance score: \(error)")
            return 0.0
        }
    }
    
    
    // MARK: - Model Predictons
    
    /// Relevance Score Calculation by the ML Model
    func updateRelevance() async {
        
        /// Handling the loading overlay
        await MainActor.run {
            isComputingRelevance = true
        }
        defer {
            Task { @MainActor in
                isComputingRelevance = false
            }
        }
        print("Predicting relevance scores...")
        
        /// Refresh cached data once at the beginning of relevance calculation cycle
        let cacheRefreshSuccess = await variableManager.refreshCachedData()
        if !cacheRefreshSuccess {
            print("Failed to refresh cached data, using fallback values")
        }
        
        /// Get cached values that will be used for all POIs
        let cachedWeather = await variableManager.getCachedWeather()
        let currentSpeed = variableManager.currentSpeed()
        let currentTheme = variableManager.currentUserTheme()
        
        for poi in allPOIs {
                /// Check if the fclass is defined in the conversion, if not -> it is not relevant and can be skipped
                guard let fclassRaw = poi.attributes["fclass"] as? String,
                      let fclass = variableManager.fclassConversion(fclass: fclassRaw) else {
                    continue
                }
                /// Convert the ID to a UUID
                if let fidAny = poi.attributes["fid"],
                   let fid = (fidAny as? NSNumber)?.int64Value {
                    /// Transform the fid value into a UUID
                    let poiID = variableManager.uuidFromFID(fid)
                    
                    /// get the attributes for the score computation ot the poi
                    let (isFavorite, clickCount, daysAgo) = variableManager.getPOIDetails(poiID: poiID)
                    let (open, hasOpeningHours) = variableManager.isOpen(otherTags: poi.attributes["other_tags"] as! String)
                    let distance = await variableManager.calculateDistanceToUser(origin: poi)
                    let hasName = variableManager.hasName(poi: poi)
                                        
                    /// compute the relevance Score using cached values
                    let score = relevanceModelManager.predictRelevance(
                        distance: distance,
                        speed: currentSpeed,
                        weather: cachedWeather,
                        isOpen: open,
                        favorite: isFavorite,
                        clickCount: clickCount,
                        lastClickedDate: daysAgo,
                        theme: currentTheme,
                        fclass: fclass,
                        hasName: hasName,
                        hasOpeningHours: hasOpeningHours
                    )
                    /// Simple main thread dispatch
                    await MainActor.run {
                        dataManager.saveRelevanceScore(for: poiID, score: score)
                    }
                } else {
                    print("Missing or invalid 'osm_id' for POI: \(poi.attributes)")
                }

        }
    }
    
    /// Update theme and notify UI on main thread
    private func updateTheme() async {
        let predictedTheme = await thematicModelManager.predictTheme(
            timeOfDay: variableManager.currentTimeOfDay(),
            dayOfWeek: variableManager.currentDay(),
            environmentType: await variableManager.currentEnvironment()
        )
        
        await MainActor.run {
            // Save the newly predicted theme
            dataManager.saveTheme(theme: predictedTheme)
            
            // Notify SettingsManager of the change
            NotificationCenter.default.post(
                name: .themeDidChange,
                object: nil,
                userInfo: ["theme": predictedTheme]
            )
            print("Theme predicted on startup: \(predictedTheme)")
        }
    }
    
    
    // MARK: - User Interactions
    
    func markPOIAsFavorite(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, context: context, isFavorite: true)
        }
    }
        
    func recordPOIClick(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, context: context)
        }
    }
    
    // MARK: - Cache Management
        
    /// Manually refresh cached data (useful for testing or when user changes location significantly)
    func refreshCache() async {
        print("Manually refreshing cache...")
        variableManager.invalidateCache()
        let success = await variableManager.refreshCachedData()
        if success {
            print("Cache refreshed successfully")
            // Optionally recalculate relevance scores with new data
            await updateRelevance()
            await loadRelevanceScores()
        } else {
            print("Failed to refresh cache")
        }
    }
    
    // MARK: - Aggregation of Close POIs
    
    /// Generalizes close POIs such that the higher POI will be preferred and displayed
    func filterOverlappingPOIs(pois: [ArcGISFeature], threshold: Double) -> [ArcGISFeature] {
        var selectedPOIs: [ArcGISFeature] = []
        var visited = Set<Int64>()
        
        /// Get current user theme and corresponding fclasses for boosting
        let currentTheme = variableManager.currentUserTheme()
        let themeClasses = getFclassesForTheme(currentTheme)
        let themeBoost = 0.5 // Thematic Boost in percentage
        
        for poi in pois {
            guard let fidAny = poi.attributes["fid"],
                  let fid = (fidAny as? NSNumber)?.int64Value,
                  !visited.contains(fid),
                  let geometry = poi.geometry as? Point else { continue }
            
            /// Find POIs within the distance threshold
            let nearby = pois.filter { other in
                guard let otherFidAny = other.attributes["fid"],
                      let otherFid = (otherFidAny as? NSNumber)?.int64Value,
                      otherFid != fid,
                      let otherGeometry = other.geometry as? Point,
                      !visited.contains(otherFid) else { return false }
                
                let distance = GeometryEngine.distance(from: geometry, to: otherGeometry)
                return distance < threshold
            }
            
            /// Include self in group
            let group = [poi] + nearby
            
            /// Find the POI with highest relevance score
            let mostRelevant = group.max { a, b in
                let scoreA = getEffectiveScore(for: a, themeClasses: themeClasses, themeBoost: themeBoost)
                let scoreB = getEffectiveScore(for: b, themeClasses: themeClasses, themeBoost: themeBoost)
                return scoreA < scoreB
            }
            
            if let best = mostRelevant {
                selectedPOIs.append(best)
                
                /// Mark all POIs in this group as visited
                for groupPoi in group {
                    if let groupFidAny = groupPoi.attributes["fid"],
                       let groupFid = (groupFidAny as? NSNumber)?.int64Value {
                        visited.insert(groupFid)
                    }
                }
            }
        }
        
        return selectedPOIs
    }
    
    /// Calculate effective score with theme boost for POI selection
    private func getEffectiveScore(for poi: ArcGISFeature, themeClasses: [Double], themeBoost: Double) -> Double {
        let baseScore = getRelevanceScore(for: poi)
        
        /// Check if POI matches current theme
        guard let fclassRaw = poi.attributes["fclass"] as? String,
              let fclass = variableManager.fclassConversion(fclass: fclassRaw) else {
            return baseScore
        }
        
        /// Apply theme boost if POI matches current theme (or if theme is "explore" which has empty fclasses)
        let isOnTheme = themeClasses.isEmpty || themeClasses.contains(fclass)
        return isOnTheme ? baseScore + themeBoost : baseScore
    }
}
