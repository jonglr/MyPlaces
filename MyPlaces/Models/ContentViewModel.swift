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
import CoreLocation

class ContentViewModel: NSObject, ObservableObject {
    
    /// The POI Model is initialized asynchronously (Favorites Panel needs to use it therefore not private)
    var poiModel: POIModel?
    /// stores all the POIs temporarely, before the relevant ones get published in order to get displayed
    private var allPOIs: [ArcGISFeature] = []
    /// Cache for favorite POIs that are outside normal loading area
    private var remoteFavoriteCache: [Int64: ArcGISFeature] = [:]
    /// The visualization of the relevant POIs that get overlayed onto the rest of the POIs
    @Published var displayedPOIs: [ArcGISFeature] = []
    /// Exposed flag to display the loading sign in the view model
    @Published var isComputingRelevance = false
    /// Expose search location state to the UI
    @Published var isUsingSearchLocation = false
    
    /// Core Data Managers
    private let context = PersistenceController.shared.container.viewContext
    private let dataManager = DataManager.shared
    
    /// Generate Managers
    private let variableManager = VariableManager()
    private let relevanceModelManager = RelevanceModelManager()
    private let thematicModelManager = ThematicModelManager()
    
    /// Location monitoring for location changes
    private let locationManager = CLLocationManager()
    private var lastUpdateLocation: CLLocation?
    private let significantDistanceThreshold: Double = 250.0 // meters
    
    /// Throttling for location updates
    private var lastLocationUpdateTime: Date = Date(timeIntervalSince1970: 0)
    private let locationUpdateThrottle: TimeInterval = 2.0 // Minimum 2 seconds between updates
    private var currentSearchLocation: Point?
    private var relevanceUpdateTask: Task<Void, Never>?
    
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
        
        // Listen for user changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserChange),
            name: .userDidChange,
            object: nil
        )
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
                guard score > 0.4 else { return nil }
                
                /// Get fclass for thematic filtering
                guard let fclassRaw = poi.attributes["fclass"] as? String,
                      let fclass = variableManager.fclassConversion(fclass: fclassRaw) else {
                    return nil
                }
                return (poi: poi, score: score, fclass: fclass)
            }
                
            /// Separate POIs into themed and non-themed groups
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
            let filteredGeneralizedPOIs = filterOverlappingPOIs(pois: combinedPOIs, threshold: 30)
            print("Filtered POIs after aggregation: \(filteredGeneralizedPOIs.count)")
            
            /// Update displayed POIs
            self.displayedPOIs = filteredGeneralizedPOIs
            
            print("All POIs: \(allPOIs.count) Loaded Relevant POIs: \(displayedPOIs.count)")
            print("Current theme: \(currentTheme) (\(getThemeName(currentTheme)))")
        }
    }
    
    /// Load favorite POIs directly by their FIDs
        @MainActor
    func loadFavoritePOIsByFID() async {
        // Get FIDs of all user favorites
        let favoriteFIDs = dataManager.getUserFavoriteFIDs()
        guard !favoriteFIDs.isEmpty else { return }
        
        // Check which favorites are already loaded
        var missingFIDs: [Int64] = []
        for fid in favoriteFIDs {
            var found = false
            
            // Check if already in displayed POIs or all POIs
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
        
        if missingFIDs.isEmpty {
            print("All favorites already loaded")
            return
        }
        
        print("Loading \(missingFIDs.count) remote favorites by FID...")
        
        // Query the service for specific FIDs
        guard let poiModel = self.poiModel,
              let table = poiModel.featureTable else { return }
        
        do {
            if table.loadStatus != .loaded {
                try await table.load()
            }
            
            // Build WHERE clause for specific FIDs
            let fidList = missingFIDs.map { String($0) }.joined(separator: ",")
            let query = QueryParameters()
            query.whereClause = "fid IN (\(fidList))"
            
            let result = try await table.queryFeatures(using: query, queryFeatureFields: .loadAll)
            
            // Cache the loaded favorites
            for feature in result.features() {
                if let arcFeature = feature as? ArcGISFeature,
                   let fidAny = arcFeature.attributes["fid"],
                   let fid = (fidAny as? NSNumber)?.int64Value {
                    remoteFavoriteCache[fid] = arcFeature
                }
            }
            
            print("Successfully loaded remote favorites")
            
            // Notify favorites panel to refresh
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
        
        // Check all loaded POIs
        for poi in allPOIs {
            if let poiFID = poi.attributes["fid"] as? NSNumber,
               poiFID.int64Value == fid {
                return poi
            }
        }
        
        // Check remote favorites cache
        if let cached = remoteFavoriteCache[fid] {
            return cached
        }
        
        return nil
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
                    let score = scores.first?.score ?? 0.0
                    return score
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
                let otherTags = poi.attributes["other_tags"] as? String ?? ""
                let (open, hasOpeningHours) = variableManager.isOpen(otherTags: otherTags)
                let distance = variableManager.calculateDistanceToUser(origin: poi)
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
                    dataManager.saveRelevanceScore(for: poiID, score: score, fid: fid,)
                }
            } else {
                print("Missing or invalid 'osm_id' for POI: \(poi.attributes)")
            }
            
        }
    }
    
    /// Update theme and notify the UI
    private func updateTheme() async {
        // Ensure we have environment data before predicting
        let environment = await variableManager.getCachedEnvironment()
        
        let predictedTheme = thematicModelManager.predictTheme(
            timeOfDay: variableManager.currentTimeOfDay(),
            dayOfWeek: variableManager.currentDay(),
            environmentType: environment  // Use the cached value
        )
        
        print("Predicting theme ...")
        
        await MainActor.run {
            // Save the newly predicted theme
            dataManager.setPredictedTheme(theme: predictedTheme)
            dataManager.clearUserTheme()
            
            // Notify SettingsManager of the change
            NotificationCenter.default.post(
                name: .themeDidChange,
                object: nil,
                userInfo: ["theme": predictedTheme, "source": "prediction"]
            )
        }
    }
    
    
    // MARK: - User Interactions
    
    func markPOIAsFavorite(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, context: context, isFavorite: true, fid: fid)
        }
    }
    
    func recordPOIClick(poi: ArcGISFeature) {
        if let fidAny = poi.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            let poiID = variableManager.uuidFromFID(fid)
            dataManager.updatePOIInteraction(poiID: poiID, context: context, fid: fid)
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
    
    // MARK: - Location Monitoring
    
    /// Setup location monitoring for significant movement detection
    private func setupLocationMonitoring() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 50.0 // Update every 50m for monitoring
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
        
        // Add throttling for ALL location changes
        let now = Date()
        guard forceUpdate || now.timeIntervalSince(lastLocationUpdateTime) >= locationUpdateThrottle else {
            print("Location update throttled - only \(String(format: "%.1f", now.timeIntervalSince(lastLocationUpdateTime)))s since last update")
            return
        }
        
        // Ensure all required components are initialized
        guard poiModel != nil else {
            print("POI model not initialized yet, skipping location update")
            return
        }
        
        guard dataManager.currentUser() != nil else {
            print("No current user, skipping location update")
            return
        }
        
        // Cancel any ongoing operations
        relevanceUpdateTask?.cancel()
        await relevanceUpdateTask?.value
        
        // Invalidate cache when location changes
        variableManager.invalidateCache()
        
        // Determine the location to use
        let locationPoint: Point
        if let searchPoint = newLocation {
            // Validate search coordinates
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
        
        // Update throttling timestamp
        lastLocationUpdateTime = now
        
        // Check distance for user movement (not search)
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
        
        // Update search location state before any operations
        if isSearchTriggered {
            self.isUsingSearchLocation = true
            currentSearchLocation = locationPoint
            variableManager.setSearchLocationOverride(locationPoint)
            print("Search triggered location change to: \(locationPoint.x), \(locationPoint.y)")
        } else if !isSearchTriggered {
            // If this is a user location update, clear search override
            self.isUsingSearchLocation = false
            currentSearchLocation = nil
            variableManager.setSearchLocationOverride(nil)
            print("User location change to: \(locationPoint.x), \(locationPoint.y)")
        }
        
        // Add delay to ensure all systems are ready
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Reload POIs for the new location
        await reloadPOIsForLocation(locationPoint)
        
        // Start relevance calculation
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
    
    /// Unified POI reloading for any location
    @MainActor
    private func reloadPOIsForLocation(_ location: Point) async {
        guard let poiModel = self.poiModel else {
            print("POI model not available for reloading")
            return
        }
        // Load POIs around the specified location
        await poiModel.loadPOIsAroundLocation(location: location)
        
        // Update our local POI array
        self.allPOIs = poiModel.POIs
        
        print("Reloaded \(allPOIs.count) POIs for location")
    }
    
    // MARK: - Public Interface Methods
    
    /// Handle location change triggered by search
    @MainActor
    func searchLocationChange(newLocation: Point) async {
        await locationChange(
            newLocation: newLocation,
            isSearchTriggered: true
        )
    }
    
    /// Check if user has moved significantly and trigger updates
    @MainActor
    private func significantLocationChange(newLocation: CLLocation) async {
        await locationChange(
            clLocation: newLocation,
            isSearchTriggered: false
        )
    }
    
    /// clear search state and return the user's current Point (no loading yet)
    @MainActor
    func beginReturnToUserLocation() -> Point? {
        isUsingSearchLocation = false
        currentSearchLocation = nil
        variableManager.setSearchLocationOverride(nil)
        return variableManager.getCurrentLocationPoint()
    }

    /// Load relevance/POIs at the given point
    @MainActor
    func completeReturnToUserLocation(_ userLocation: Point) async {
        await locationChange(newLocation: userLocation, forceUpdate: true)
    }
    
    @MainActor
    func ensurePOIVisible(_ feature: ArcGISFeature) async {
        // Check if POI is already in displayed POIs
        if let fidAny = feature.attributes["fid"],
           let fid = (fidAny as? NSNumber)?.int64Value {
            
            let variableManager = VariableManager()
            let poiID = variableManager.uuidFromFID(fid)
            
            // If not in displayed POIs, temporarily add it with high relevance
            let isDisplayed = displayedPOIs.contains { poi in
                if let poiFidAny = poi.attributes["fid"],
                   let poiFid = (poiFidAny as? NSNumber)?.int64Value {
                    return poiFid == fid
                }
                return false
            }
            
            if !isDisplayed {
                // Temporarily add this POI to displayed POIs
                var updatedPOIs = displayedPOIs
                updatedPOIs.append(feature)
                displayedPOIs = updatedPOIs
                
                // Ensure it has a high relevance score so it shows up
                dataManager.saveRelevanceScore(for: poiID, score: 0.9, fid: fid )
            }
        }
    }
    
    @objc private func handleUserChange() {
        Task { @MainActor in
            // Clear current data
            displayedPOIs.removeAll()
            
            // Reload everything for the new user
            await updateTheme()
            await updateRelevance()
            await loadRelevanceScores()
        }
    }
    
}
    
    // MARK: - CLLocationManagerDelegate Extension

/// This is a CLLocationManagerDelegate extension that handles iOS location services callbacks. It's responsible for:
/// Receiving location updates from iOS when the user moves
/// Handling location permission changes
/// Managing location service errors

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
            // Use the unified location handler for user movement
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
            // Permission granted - start receiving location updates
            locationManager.startUpdatingLocation()
            print("Location authorization granted")
            
        case .denied, .restricted:
            // Permission denied - handle gracefully
            print("Location access denied or restricted")
            
        case .notDetermined:
            // Permission not yet requested - ask for it
            locationManager.requestWhenInUseAuthorization()
            print("Requesting location authorization")
            
        @unknown default:
            print("Unknown location authorization status")
            break
        }
    }
}
