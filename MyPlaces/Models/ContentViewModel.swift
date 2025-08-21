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
  
    
    // MARK: - Initialization
    
    /// Asynchronous Loading and calculation of the relevant of POIs
    init() {
        Task {
            await initializePOIModel()
            await updateTheme()
            await updateRelevance()
            await loadRelevanceScores()
        }
    }
    
    /// Async Initialization of the POIModel
    @MainActor
    private func initializePOIModel() async {
        let model = await POIModel(variableManager: variableManager) // Initialize asynchronously
        self.poiModel = model
        self.allPOIs = model.POIs
    }
    
    /// Load Relevance Scores and Filter POIs
    @MainActor
    func loadRelevanceScores() async {
        guard dataManager.currentUser() != nil else {
            print("No user logged in.")
            return
        }
        guard let allPOIs = poiModel?.POIs else {
            print("POI model not initialized")
            return
        }
        
        /// Filter POIs that have relevance scores > 0.6
        let filteredPOIs = allPOIs.filter { poi in
            let score = getRelevanceScore(for: poi)
            return score > 0.6
        }
        print("Filtered POIs before aggregation: \(filteredPOIs.count)")
        
        /// Apply aggregation to remove overlapping POIs
        let filteredGeneralizedPOIs = filterOverlappingPOIs(pois: filteredPOIs, threshold: 10)
        print("Filtered POIs after aggregation: \(filteredGeneralizedPOIs.count)")
        
        /// Update displayed POIs
        self.displayedPOIs = filteredGeneralizedPOIs
        
        print("All POIs: \(allPOIs.count) Loaded Relevant POIs: \(displayedPOIs.count)")
    }
    
    /// Helper function to get relevance score for a POI
    private func getRelevanceScore(for poi: ArcGISFeature) -> Double {
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
                    let distance = variableManager.calculateDistanceToUser(origin: poi)
                    let hasName = variableManager.hasName(poi: poi)
                    
                    /// compute the relevance Score
                    let score = await relevanceModelManager.predictRelevance(
                        distance: distance,
                        speed: variableManager.currentSpeed(),
                        weather: variableManager.currentWeather(),
                        isOpen: open,
                        favorite: isFavorite,
                        clickCount: clickCount,
                        lastClickedDate: daysAgo,
                        theme: variableManager.currentUserTheme(),
                        fclass: fclass,
                        hasName: hasName,
                        hasOpeningHours: hasOpeningHours
                    )
                    /// Safe the Relevance Score
                    dataManager.saveRelevanceScore(for: poiID, score: score)
                    print("Predicted relevance score for \(poiID): \(score)")
                } else {
                    print("Missing or invalid 'osm_id' for POI: \(poi.attributes)")
                }

        }
    }
    
    /// Map theme choice by the ML Model
    func updateTheme() async {
        let thematicChoice = await thematicModelManager.predictTheme(timeOfDay: variableManager.currentTimeOfDay(), dayOfWeek: variableManager.currentDay(), environmentType: variableManager.currentEnvironment())
        dataManager.saveTheme(theme: thematicChoice)
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
    
    // MARK: - Aggregation of Close POIs
    
    /// Generalizes close POIs such that the higher POI will be prefered and displayed (Threshold is 50m for a aggregatioon)
    func filterOverlappingPOIs(pois: [ArcGISFeature], threshold: Double) -> [ArcGISFeature] {
        var selectedPOIs: [ArcGISFeature] = []
        var visited = Set<Int64>()
        
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
                
                return variableManager.calculateDistance(from: geometry, to: otherGeometry) < threshold
            }
            
            /// Include self in group
            let group = [poi] + nearby
            
            /// Find the POI with highest interest score
            let mostRelevant = group.max { a, b in
                let scoreA = getRelevanceScore(for: a)
                let scoreB = getRelevanceScore(for: b)
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
}
