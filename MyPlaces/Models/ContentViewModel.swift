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
        let model = await POIModel() // Initialize asynchronously
        self.poiModel = model
        self.allPOIs = model.POIs
        print ("loaded POIs")
    }
    
    /// Load Relevance Scores and Filter POIs
    @MainActor
    func loadRelevanceScores() async {
        guard let user = dataManager.currentUser() else {
            print("No user logged in.")
            return
        }
        let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
        /// Load the POIs with the scores higher than 0.5
        request.predicate = NSPredicate(format: "user == %@ AND score > 0.5", user)
        do {
            let scores = try context.fetch(request)
            let filteredPOIs = poiModel?.POIs.filter { poi in
                guard let poiID = poi.attributes["id"] as? UUID else { return false }
                return scores.contains(where: { $0.poiID == poiID })
            } ?? []
            /// publish the POIs
            self.displayedPOIs = filteredPOIs
            print("Loaded Relevant POIs: \(displayedPOIs.count)")
        } catch {
            print("Error loading relevance scores: \(error)")
        }
    }
    
    
    // MARK: - Model Predictons
    
    /// Relevance Score Calculation by the ML Model
    func updateRelevance() async {
        for poi in allPOIs {
            /// Convert the ID to a UUID
            if let fidAny = poi.attributes["fid"],
               let fid = (fidAny as? NSNumber)?.int64Value {
                let poiID = variableManager.uuidFromFID(fid)
                
                /// get the attribute value pairs
                let (isFavorite, clickCount, daysAgo) = variableManager.getPOIDetails(poiID: poiID)
                let open = variableManager.isOpen(otherTags: poi.attributes["opening_hours"] as! String)
                
                /// compute the relevance Score
                let score = await relevanceModelManager.predictRelevance(
                    distance: variableManager.calculateDistance(origin: poi),
                    speed: variableManager.currentSpeed(),
                    weather: variableManager.currentWeather(),
                    isOpen: open,
                    favorite: isFavorite,
                    clickCount: clickCount,
                    lastClickedDate: daysAgo,
                    theme: variableManager.currentUserTheme(),
                    fclass: variableManager.fclassConversion(fclass: poi.attributes["fclass"] as! String))
                /// Safe the Relevance Score
                dataManager.saveRelevanceScore(for: poiID, score: score)
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
    
    func changeTheme(theme: String) {
        dataManager.saveTheme(theme: theme)
    }
    
    func markPOIAsFavorite(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            DataManager.shared.updatePOIInteraction(poiID: poiID, context: context, isFavorite: true)
        }
    }
        
    func recordPOIClick(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            DataManager.shared.updatePOIInteraction(poiID: poiID, context: context)
        }
    }
    
}
