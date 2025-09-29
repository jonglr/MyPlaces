//
//  ContentViewModel.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Functions**
/// Manages user interactions with the MapView and processes the whole logic behind it.
/// This file is separated into different functionality topics:
/// - Variable Declaration
/// - Initialization
/// - Relevance Predictions
/// - Thematic Predictions
/// - POI Handling
/// - POI Aggregation
/// - User Interactions
/// - Location Monitoring
/// - Location Change Public Interface Methods (related to the Location Monitoring)
/// - CLLocationManagerDelegate Extension

import SwiftUI
import CoreData
import ArcGIS
import CoreLocation

class ContentViewModel: NSObject, ObservableObject {

    // MARK: - Variable Declaration
    
    
    /// The POI Model is initialized asynchronously (Favorites Panel needs to use it therefore not private)
    var poiModel: POIModel?
    /// Generate Managers
    let variableManager = VariableManager()
    private let relevanceModelManager = RelevanceModelManager()
    private let thematicModelManager = ThematicModelManager()
    private let dataManager = DataManager.shared
    
    /// All POI Storage (temporarely) before the relevant ones get published in order to get displayed
    var allPOIs: [ArcGISFeature] = []
    /// Relevant POIs that get overlayed onto the rest of the POIs
    @Published var displayedPOIs: [ArcGISFeature] = []
    /// Favorite POI Cache that are outside normal loading area
    private var remoteFavoriteCache: [Int64: ArcGISFeature] = [:]
    
    /// Location monitoring variables for location changes
    private let locationManager = CLLocationManager()
    private var lastUpdateLocation: CLLocation?
    private let significantDistanceThreshold: Double = 250.0 /// meters
    
    /// Throttling for location updates
    private var lastLocationUpdateTime: Date = Date(timeIntervalSince1970: 0)
    private let locationUpdateThrottle: TimeInterval = 2.0 /// Minimum 2 seconds between updates
    var currentSearchLocation: Point?
    private var relevanceUpdateTask: Task<Void, Never>?
    
    /// Aggregation control properties
    @Published var currentMapScale: Double = 1500 /// Default scale
    var lastAggregationScale: Double = 0
    private var aggregationTask: Task<Void, Never>?
    var unfilteredRelevantPOIs: [ArcGISFeature] = [] /// Store POIs before aggregation
    /// Threshold for scale change to trigger re-aggregation
    private let scaleChangeThreshold: Double = 0.25 /// 25% change
    
    /// Exposed flag to display the loading sign in the view model
    @Published var isComputingRelevance = false
    
    /// Expose search location state to the UI
    @Published var isUsingSearchLocation = false
    /// Search Attributes
    let graphicsOverlay = GraphicsOverlay()
    let locator = LocatorTask(
        url: URL(string: "https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer")!
    )
    
    
    // MARK: - Initialization
    
    
    /// Asynchronous Loading and calculation of the relevant of POIs
    override init() {
        super.init()
        
        Task { @MainActor in
            await initializePOIModel()
            let cacheSuccess = await variableManager.refreshCachedData()
            if !cacheSuccess {
                print("Warning: Could not refresh cache before theme prediction")
            }
            await updateTheme()
            await updateRelevance()
            await loadRelevanceScores()
        }
        
        setupLocationMonitoring()
        
        /// Listen for user changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserChange),
            name: .userDidChange,
            object: nil
        )
    }
    
    /// Sets up the initialization of the map view for a new user
    @objc private func handleUserChange() {
        Task { @MainActor in
            /// Clear current data
            displayedPOIs.removeAll()
            
            /// Reload everything for the new user
            await updateTheme()
            await updateRelevance()
            await loadRelevanceScores()
        }
    }
    
    
    // MARK: - Relevance Predictions
    
    
    /// Load Relevance Scores from Core Data and Filter the POIs which will be displayed later
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
            
            /// Get current user theme
            let currentTheme = variableManager.currentUserTheme()
        
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
            
            /// Combine all POIs and store them for re-aggregation
            self.unfilteredRelevantPOIs = (relevantPOIs).map { $0.poi }
            print("Total POIs before aggregation: \(unfilteredRelevantPOIs.count)")
            
            /// Apply initial aggregation with current scale
            await performAggregation()
            
            print("All POIs: \(allPOIs.count) Loaded Relevant POIs: \(displayedPOIs.count)")
            print("Current theme: \(currentTheme) (\(getThemeName(currentTheme)))")
    }
    
    /// Helper function to get relevance score for a POI
    func getRelevanceScore(for poi: ArcGISFeature) -> Double {
        guard let fidAny = poi.attributes["fid"],
              let fid = (fidAny as? NSNumber)?.int64Value else { return 0.0 }
        
        let poiID = variableManager.uuidFromFID(fid)
        
        var score: Double = 0.0
        let context = PersistenceController.shared.container.viewContext
        context.performAndWait {
            guard let user = dataManager.currentUser(),
                  let userID = user.userID else { return }
            
            let request: NSFetchRequest<RelevanceScore> = RelevanceScore.fetchRequest()
            request.predicate = NSPredicate(
                format: "userID == %@ AND poiID == %@",
                userID as CVarArg,
                poiID as CVarArg
            )
            do {
                let scores = try context.fetch(request)
                if let relevanceScore = scores.first {
                    score = relevanceScore.score
                }
            } catch {
                print("Error fetching relevance score: \(error)")
            }
        }
        return score
    }
    
    /// Relevance Score Calculation by the ML Model
    @MainActor
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
        
        /// Refresh cached data once at the beginning
        let cacheRefreshSuccess = await variableManager.refreshCachedData()
        if !cacheRefreshSuccess {
            print("Failed to refresh cached data, using fallback values")
        }
        
        /// Get cached values that will be used for all POIs
        let cachedWeather = await variableManager.getCachedWeather()
        let currentSpeed = variableManager.currentSpeed()
        let currentTheme = variableManager.currentUserTheme()
        
        /// Collect scores for batch saving
        var scoresToSave: [(poiID: UUID, score: Double, fid: Int64, relevanceData: String?)] = []
        
        for poi in allPOIs {
            /// Check if the fclass is defined in the conversion
            guard let fclassRaw = poi.attributes["fclass"] as? String,
                  let fclass = variableManager.fclassConversion(fclass: fclassRaw) else {
                continue
            }
            
            /// Convert the ID to a UUID
            if let fidAny = poi.attributes["fid"],
               let fid = (fidAny as? NSNumber)?.int64Value {
                /// Transform the fid value into a UUID
                let poiID = variableManager.uuidFromFID(fid)
                
                /// get the attributes for the score computation
                let (isFavorite, clickCount, daysAgo) = variableManager.getPOIDetails(poiID: poiID)
                let otherTags = poi.attributes["other_tags"] as? String ?? ""
                let (open, _) = variableManager.isOpen(otherTags: otherTags)
                let distance = variableManager.calculateDistanceToUser(origin: poi)
                let clusterScore = poi.attributes["cluster_score"] as! Double
                let colocationScore = poi.attributes["colocation_score"] as! Double
                
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
                    clusterScore: clusterScore,
                    colocationScore: colocationScore
                )
                
                /// Create dictionary with all the data
                let relevanceAttributes: [String: Any] = [
                    "distance": distance,
                    "speed": currentSpeed,
                    "weather": cachedWeather,
                    "isOpen": open,
                    "favorite": isFavorite,
                    "clickCount": clickCount,
                    "lastClickedDate": daysAgo,
                    "theme": currentTheme,
                    "fclass": fclass,
                    "clusterScore": clusterScore,
                    "colocationScore": colocationScore,
                    "score": score,
                    "timestamp": Date().timeIntervalSince1970
                ]
                
                /// Convert to a JSON String for CoreData saving
                let jsonData = try? JSONSerialization.data(withJSONObject: relevanceAttributes)
                let jsonString = jsonData != nil ? String(data: jsonData!, encoding: .utf8) : nil
                
                scoresToSave.append((poiID: poiID, score: score, fid: fid, relevanceData: jsonString))
            } else {
                print("Missing or invalid 'osm_id' for POI: \(poi.attributes)")
            }
        }
        
        /// Batch save all scores at once
        await MainActor.run {
            for scoreData in scoresToSave {
                dataManager.saveRelevanceScore(
                    for: scoreData.poiID,
                    score: scoreData.score,
                    fid: scoreData.fid,
                    relevanceData: scoreData.relevanceData
                )
            }
        }
    }
    
    
    // MARK: - Thematic Predictions
    
    
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
    
    /// Update theme and notify the UI
    func updateTheme() async {
        /// Ensure that there is environment data available before predicting the theme
        let environment = await variableManager.getCachedEnvironment()
        
        let predictedTheme = thematicModelManager.predictTheme(
            timeOfDay: variableManager.currentTimeOfDay(),
            dayOfWeek: variableManager.currentDay(),
            environmentType: environment  // Use the cached value
        )
        
        print("Predicting theme ...")
        
        await MainActor.run {
            /// Save the newly predicted theme
            dataManager.setPredictedTheme(theme: predictedTheme)
            dataManager.clearUserTheme()
            
            /// Notify SettingsManager of the theme change
            NotificationCenter.default.post(
                name: .themeDidChange,
                object: nil,
                userInfo: ["theme": predictedTheme, "source": "prediction"]
            )
        }
    }
    
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
    
    
    // MARK: - POI Handling
    
    
    /// Async Initialization of the POIModel
    @MainActor
    private func initializePOIModel() async {
        let model = await POIModel(variableManager: variableManager)
        await MainActor.run {
            self.poiModel = model
            self.allPOIs = model.POIs
        }
    }
    
    /// Load favorite POIs directly by their FIDs
    @MainActor
    func loadFavoritePOIsByFID() async {
        /// Get FIDs of all user favorites
        let favoriteFIDs = dataManager.getUserFavoriteFIDs()
        guard !favoriteFIDs.isEmpty else { return }
        
        /// Check which favorites are already loaded
        var missingFIDs: [Int64] = []
        for fid in favoriteFIDs {
            var found = false
            
            /// Check if already in displayed POIs or all POIs
            for poi in allPOIs {
                if let poiFID = poi.attributes["fid"] as? NSNumber,
                   poiFID.int64Value == fid {
                    found = true
                    break
                }
            }
            
            if !found && remoteFavoriteCache[fid] == nil {
                missingFIDs.append(fid)
            }
        }
        
        /// If all POIs are found -> end function
        if missingFIDs.isEmpty {
            return
        }
        
        print("Loading \(missingFIDs.count) remote favorites by FID...")
        
        /// Query the service for specific FIDs
        guard let poiModel = self.poiModel,
              let table = poiModel.featureTable else { return }
        
        do {
            if table.loadStatus != .loaded {
                try await table.load()
            }
            
            /// Build a WHERE clause for the specific FIDs of the favorite POIs
            let fidList = missingFIDs.map { String($0) }.joined(separator: ",")
            let query = QueryParameters()
            query.whereClause = "fid IN (\(fidList))"
            
            let result = try await table.queryFeatures(using: query, queryFeatureFields: .loadAll)
            
            /// Cache the loaded favorites
            for feature in result.features() {
                if let arcFeature = feature as? ArcGISFeature,
                   let fidAny = arcFeature.attributes["fid"],
                   let fid = (fidAny as? NSNumber)?.int64Value {
                    remoteFavoriteCache[fid] = arcFeature
                }
            }
            
            print("Successfully loaded remote favorites")
            
            /// Notify favorites panel to refresh the favorite POI locations
            NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
            
        } catch {
            print("Error loading remote favorites: \(error)")
        }
    }
    
    /// Find POI by FID from any source
    func findPOIByFID(_ fid: Int64) -> ArcGISFeature? {
        // Check displayed POIs
        for poi in displayedPOIs {
            if let poiFID = poi.attributes["fid"] as? NSNumber,
               poiFID.int64Value == fid {
                return poi
            }
        }
        
        /// Check all loaded POIs
        for poi in allPOIs {
            if let poiFID = poi.attributes["fid"] as? NSNumber,
               poiFID.int64Value == fid {
                return poi
            }
        }
        
        /// Check remote favorites cache (if not already loaded)
        if let cached = remoteFavoriteCache[fid] {
            return cached
        }
        
        return nil
    }
    
    /// POI reloading for a specific location
    @MainActor
    func reloadPOIsForLocation(_ location: Point) async {
        guard let poiModel = self.poiModel else {
            print("POI model not available for reloading")
            return
        }
        /// Load POIs around the specified location
        await poiModel.loadPOIsAroundLocation(location: location)
        
        /// Update our local POI array
        self.allPOIs = poiModel.POIs
        
        print("Reloaded \(allPOIs.count) POIs for location")
    }
    
    /// Make a POI temporarely visible
    @MainActor
    func ensurePOIVisible(_ feature: ArcGISFeature) async {
        /// Check if POI is already in displayed POIs
        if let fidAny = feature.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            
            let variableManager = VariableManager()
            let poiID = variableManager.uuidFromFID(fid)
            
            /// If not in displayed POIs, temporarily add it with high relevance
            let isDisplayed = displayedPOIs.contains { poi in
                if let poiFidAny = poi.attributes["fid"],
                   let poiFid = (poiFidAny as? NSNumber)?.int64Value {
                    return poiFid == fid
                }
                return false
            }
            
            if !isDisplayed {
                /// Temporarily add this POI to displayed POIs
                var updatedPOIs = displayedPOIs
                updatedPOIs.append(feature)
                displayedPOIs = updatedPOIs
                
                /// Ensure it has a high relevance score so it shows up
                dataManager.saveRelevanceScore(for: poiID, score: 1.0, fid: fid )
            }
        }
    }
    
    
    // MARK: - POI Aggregation
    
    /// Defines the cluster distance for the POI aggregation
    private func getAggregationThreshold(for scale: Double) -> Double {
        switch scale {
        case 0..<200:
            return 10.0
        case 200..<500:
            return 20.0
        case 500..<1000:
            return 45.0
        case 1000..<1600:
            return 60.0
        case 1600..<2000:
            return 75.0
        case 2000..<2500:
            return 80.0
        case 2500..<3000:
            return 100.0
        case 3000..<4000:
            return 150.0
        case 4000..<6000:
            return 200.0
        case 6000..<10000:
            return 300.0
        case 10000..<15000:
            return 400.0
        case 15000..<30000:
            return 500.0
        default:
            return 1000.0
        }
    }
    
    /// Trigger re-aggregation when scale changes significantly
        @MainActor
    func handleMapScaleChange(newScale: Double) async {
        /// Check if scale changed significantly (more than threshold)
        let scaleChangeRatio = abs(newScale - lastAggregationScale) / max(lastAggregationScale, 1)
        
        guard scaleChangeRatio > scaleChangeThreshold else {
            /// Scale change too small, skip re-aggregation
            return
        }
        
        currentMapScale = newScale
        
        /// Cancel any pending aggregation
        aggregationTask?.cancel()
        
        /// Debounce: wait 100ms before aggregating
        aggregationTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) /// 0.1 seconds
            
            guard !Task.isCancelled else { return }
            
            await performAggregation()
            lastAggregationScale = newScale
        }
    }
    
    /// Perform the actual aggregation with current scale
    @MainActor
    private func performAggregation() async {
        guard !unfilteredRelevantPOIs.isEmpty else { return }
        
        let threshold = getAggregationThreshold(for: currentMapScale)
        print("Aggregating POIs with threshold: \(threshold)m at scale: \(currentMapScale)")
        
        let aggregatedPOIs = filterOverlappingPOIs(
            pois: unfilteredRelevantPOIs,
            threshold: threshold
        )
        
        /// Update displayed POIs
        self.displayedPOIs = aggregatedPOIs
        
        print("Aggregation complete: \(unfilteredRelevantPOIs.count) -> \(aggregatedPOIs.count) POIs")
    }
    
    /// Quickly re-aggregate existing POIs without recalculating relevance
    @MainActor
    func quickReaggregate() async {
        guard !unfilteredRelevantPOIs.isEmpty else {
            print("No POIs to re-aggregate")
            return
        }
        await performAggregation()
    }
    
    /// Generalizes close POIs such that the higher POI will be preferred and displayed
    func filterOverlappingPOIs(pois: [ArcGISFeature], threshold: Double) -> [ArcGISFeature] {
        var selectedPOIs: [ArcGISFeature] = []
        var visited = Set<Int64>()
        
        /// Get current user theme and corresponding fclasses for boosting
        let currentTheme = variableManager.currentUserTheme()
        let themeClasses = getFclassesForTheme(currentTheme)
        let themeBoost = 50.0 /// Thematic Boost in percentage
        let thresholdSq = threshold * threshold
        
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
                
                let dx = geometry.x - otherGeometry.x
                let dy = geometry.y - otherGeometry.y
                           
                /// Quick bounding-box reject
                if abs(dx) > threshold || abs(dy) > threshold {
                    return false
                }
                /// Squared distance check
                return dx*dx + dy*dy < thresholdSq
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
    
    
    // MARK: - User Interactions
    
    
    func markPOIAsFavorite(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, isFavorite: true, fid: fid)
        }
    }
    
    func recordPOIClick(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, fid: fid)
        }
    }
    
    
    // MARK: - Location Monitoring
    
    
    /// Setup location monitoring for significant movement detection
    private func setupLocationMonitoring() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0 /// Update every 5m for monitoring
    }
    
    /// Handle location changes from either user movement or search
    @MainActor
    private func locationChange(
        newLocation: Point? = nil,
        clLocation: CLLocation? = nil,
        isSearchTriggered: Bool = false,
        forceUpdate: Bool = false
    ) async {
        if isUsingSearchLocation && !isSearchTriggered {
            print("Ignoring location change - currently using search location")
            return
        }
        
        /// Add throttling for ALL location changes
        let now = Date()
        guard forceUpdate || now.timeIntervalSince(lastLocationUpdateTime) >= locationUpdateThrottle else {
            print("Location update throttled - only \(String(format: "%.1f", now.timeIntervalSince(lastLocationUpdateTime)))s since last update")
            return
        }
        
        /// Ensure all required components are initialized
        guard poiModel != nil else {
            return
        }
        guard dataManager.currentUser() != nil else {
            return
        }
        
        /// Cancel any ongoing operations
        relevanceUpdateTask?.cancel()
        await relevanceUpdateTask?.value
        
        /// Invalidate cache when location changes
        variableManager.invalidateCache()
        
        /// Determine the location to use
        let locationPoint: Point
        if let searchPoint = newLocation {
            /// Validate search coordinates
            guard abs(searchPoint.x) <= 180 && abs(searchPoint.y) <= 90 else {
                print("Invalid search coordinates: \(searchPoint.x), \(searchPoint.y)")
                return
            }
            locationPoint = searchPoint
        } else if let clLoc = clLocation {
            locationPoint = Point(
                x: clLoc.coordinate.longitude,
                y: clLoc.coordinate.latitude,
                spatialReference: .wgs84
            )
        } else {
            print("No valid location provided")
            return
        }
        
        /// Update throttling timestamp
        lastLocationUpdateTime = now
        
        /// Check distance for user movement (not search)
        if !isSearchTriggered, let currentCLLocation = clLocation {
            if let lastLocation = lastUpdateLocation {
                let distance = currentCLLocation.distance(from: lastLocation)
                guard forceUpdate || distance >= significantDistanceThreshold else {
                    print("User movement too small: \(Int(distance))m")
                    return
                }
                print("User moved \(Int(distance))m - triggering update")
            }
            lastUpdateLocation = currentCLLocation
        }
        
        /// Update search location state before any operations
        if isSearchTriggered {
            self.isUsingSearchLocation = true
            currentSearchLocation = locationPoint
            variableManager.setSearchLocationOverride(locationPoint)
            print("Search triggered location change to: \(locationPoint.x), \(locationPoint.y)")
        } else if !isSearchTriggered {
            /// If this is a user location update, clear search override
            self.isUsingSearchLocation = false
            currentSearchLocation = nil
            variableManager.setSearchLocationOverride(nil)
            print("User location change to: \(locationPoint.x), \(locationPoint.y)")
        }
        
        /// Add delay to ensure all systems are ready
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        /// Reload POIs for the new location
        await reloadPOIsForLocation(locationPoint)
        
        /// Start relevance calculation
        relevanceUpdateTask = Task {
            guard !Task.isCancelled else { return }
            let cacheSuccess = await variableManager.refreshCachedData()
            if !cacheSuccess {
                print("Warning: Cache refresh failed at new location")
            }
            
            guard !Task.isCancelled else { return }
            await updateTheme()
            
            guard !Task.isCancelled else { return }
            await updateRelevance()
            
            guard !Task.isCancelled else { return }
            await loadRelevanceScores()
            
            print("Location workflow completed for: \(locationPoint.x), \(locationPoint.y)")
        }
        
        await relevanceUpdateTask?.value
    }
    
    
    // MARK: - Location Change Public Interface Methods
    
    
    /// Handle location change triggered by search
    @MainActor
    func searchLocationChange(newLocation: Point) async {
        await locationChange(
            newLocation: newLocation,
            isSearchTriggered: true
        )
    }
    
    /// Check if user has moved significantly and trigger updates (Handle Location Change triggered by user location movement)
    @MainActor
    private func significantLocationChange(newLocation: CLLocation) async {
        await locationChange(
            clLocation: newLocation,
            isSearchTriggered: false
        )
    }
    
    /// Clear search state and return the user's current Point (no loading yet)
    @MainActor
    func beginReturnToUserLocation() -> Point? {
        isUsingSearchLocation = false
        currentSearchLocation = nil
        variableManager.setSearchLocationOverride(nil)
        return variableManager.getCurrentLocationPoint()
    }

    /// Change the location back to the user location and force update
    @MainActor
    func completeReturnToUserLocation(_ userLocation: Point) async {
        await locationChange(
            newLocation: userLocation,
            forceUpdate: true
        )
    }
}
    

    // MARK: - CLLocationManagerDelegate Extension


/// This is a CLLocationManagerDelegate extension that handles iOS location services callbacks. It's responsible for:
/// - Receiving location updates from iOS when the user moves
/// - Handling location permission changes
/// - Managing location service errors

extension ContentViewModel: CLLocationManagerDelegate {
    
    /// Called automatically by iOS when user location changes
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        guard !isUsingSearchLocation else {
                    print("Ignoring location update - currently using search location override")
                    return
                }
                
                Task {
                    await significantLocationChange(newLocation: newLocation)
                }
        
        Task {
            /// Use the unified location handler for user movement
            await locationChange(
                clLocation: newLocation,
                isSearchTriggered: false
            )
        }
    }
    
    /// Called when location services encounter an error
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    /// Called when location permission status changes
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            /// Permission granted - start receiving location updates
            locationManager.startUpdatingLocation()
            print("Location authorization granted")
            
        case .denied, .restricted:
            /// Permission denied - handle gracefully
            print("Location access denied or restricted")
            
        case .notDetermined:
            /// Permission not yet requested - ask for it
            locationManager.requestWhenInUseAuthorization()
            print("Requesting location authorization")
            
        @unknown default:
            print("Unknown location authorization status")
            break
        }
    }
}
