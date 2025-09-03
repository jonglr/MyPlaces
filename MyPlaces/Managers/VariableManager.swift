//
//  WeatherManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 14.04.2025.
//

/// **Class Functions**
/// Computes the Attributes to hand over to the ContentViewModel in the correct format to input them into the RelevanceModel and ThematicModel for relevance calculations

import Foundation
import CryptoKit
import ArcGIS
import CoreData
import CoreLocation


class VariableManager {
    
    private let dataManager = DataManager.shared
    private let context = PersistenceController.shared.container.viewContext
    
    private var weatherTask: Task<Double, Never>?
    private var environmentTask: Task<Double, Never>?
    
    private var currentThemeString: String = "explore"
    
    /// Override location for search-based POI loading
    private var searchLocationOverride: Point?
    private var isUsingSearchLocation = false
    
    init() {
        currentThemeString = resolveEffectiveTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onThemeChanged(_:)),
            name: .themeDidChange,
            object: nil
        )
    }
    
    @objc private func onThemeChanged(_ n: Notification) {
        currentThemeString = resolveEffectiveTheme()
        print("Effective theme = \(currentThemeString)")
    }
    
    private func resolveEffectiveTheme() -> String {
        let s = DataManager.shared.fetchThemeState()
        return s.userTheme ?? s.predictedTheme ?? "explore"
    }
    
    // MARK: - Cache Management
        
    private var cachedData: CachedData?
    
    private struct CachedData {
        let weather: Double
        let environment: Double
        let userLocation: Point
        let timestamp: Date
        
        var isValid: Bool {
            // Cache is valid for 15s
            return Date().timeIntervalSince(timestamp) < 15
        }
    }
        
    /// Refreshes cached data (weather, environment, user location) for relevance calculations
    func refreshCachedData() async -> Bool {
        /// Check if cache is still valid
        if let cached = cachedData, cached.isValid {
            return true
        }

        /// Get current user location
        guard let currentLocation = getEffectiveLocationPoint() else {
            print("Failed to get location for cache refresh")
            return false
        }
        
        print("Refreshing cached data...")
        
        /// cancel existing tasks
        weatherTask?.cancel()
        environmentTask?.cancel()
        
        /// Create new tasks
        weatherTask = Task { await currentWeather(for: currentLocation) }
        environmentTask = Task { await currentEnvironment(for: currentLocation) }
                
        /// Wait for both
        let weather = await weatherTask?.value ?? 2.0
        let environment = await environmentTask?.value ?? 1.0
        
        /// Cache the new data
        cachedData = CachedData(
            weather: weather,
            environment: environment,
            userLocation: currentLocation,
            timestamp: Date()
        )
        
        print("Cache refreshed - Weather: \(weather), Environment: \(environment)")
        return true
    }
        
    /// Returns cached weather data, refreshes cache if needed
    func getCachedWeather() async -> Double {
        if await refreshCachedData() {
            return cachedData?.weather ?? 2.0
        }
        return 2.0 // Default: cloudy
    }
        
    /// Returns cached environment data, refreshes cache if needed
    func getCachedEnvironment() async -> Double {
        if await refreshCachedData() {
            return cachedData?.environment ?? 1.0
        }
        return 1.0 // Default: rural
    }
        
    /// Forces cache invalidation (useful for testing or manual refresh)
    func invalidateCache() {
        cachedData = nil
        print("Cache invalidated")
    }
    
    // MARK: - Convertors
    
    /// converts the fclasses into corresponding doubles for the model input
    func fclassConversion(fclass: String) -> Double? {
        guard let url = Bundle.main.url(forResource: "fclass_mapping", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let mapping = try? JSONDecoder().decode([String: Double].self, from: data) else {
                print("Failed to load or decode fclass_mapping.json")
                return nil
            }
            return mapping[fclass]
    }
    
    /// Generate UUID of the "fid" from the poi which results in a consistant output conversion
    func uuidFromFID(_ fid: Int64) -> UUID {
        let string = String(fid)
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        let uuidData = Data(hash.prefix(16))
        return uuidData.withUnsafeBytes {
            UUID(uuid: $0.load(as: uuid_t.self))
        }
    }
    
    /// Fetches and converts the Thematic Choice of the model (or user)
    func currentUserTheme() -> Double {
        let map: [String: Double] = [
            "shopping": 0, "food": 1, "public transport": 2,
            "culture": 3, "outdoor": 4, "explore": 5
        ]
        return map[currentThemeString, default: 5]
    }
    
    // MARK: - Basic Location Variables
    
    
    /// returns the current time in the hourly versions [0, 1, ... , 23]
    func currentTimeOfDay() -> Double {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        return Double(currentHour)
    }
    
    /// Returns the current day of the week as an integer (0 to 6, Mon=0, Sun=6)
    func currentDay() -> Double {
        let calendar = Calendar.current
        let currentDay = (calendar.component(.weekday, from: Date()) + 5) % 7
        return Double(currentDay)
    }
    
    /// Calculates the current speed of the device in km/h
    func currentSpeed() -> Double {
        let locationManager = CLLocationManager()
        if let speed = locationManager.location?.speed, speed >= 0 {
            /// Convert m/s to km/h
            return speed * 3.6
        }
        return 0.0
    }
    
    
    // MARK: - External Information Retrieval
    
    /// Fetches the context score (0 = urban, 1 = rural, 2 = nature) at the given location.
    func currentEnvironment() async -> Double {
        // Use cached version if available
        if let cached = cachedData, cached.isValid {
            return cached.environment
        }
        
        /// Get current location and fetch environment
        guard let point = getCurrentLocationPoint() else {
            print("No valid user location.")
            return 1.0
        }
        
        return await currentEnvironment(for: point)
    }
        
    /// Fetches environment data for a specific location (used internally by caching system)
    private func currentEnvironment(for point: Point) async -> Double {
        do {
            let serviceItem = PortalItem(
                portal: .arcGISOnline(connection: .authenticated),
                id: Item.ID("ffcc3b01c5754a7b9e98ed3b959d73d2")!
            )
            let serviceFeatureTable = ServiceFeatureTable(item: serviceItem)
            try await serviceFeatureTable.load()
            
            let queryParams = QueryParameters()
            queryParams.geometry = point
            queryParams.spatialRelationship = .intersects
            queryParams.whereClause = "1=1"
            let result = try await serviceFeatureTable.queryFeatures(using: queryParams, queryFeatureFields: .loadAll)
            for feature in result.features() {
                let desc = feature.attributes["DESC_VAL"]
                return self.envTypeToDouble(from: desc as! String)
            }
        } catch {
            print("Error querying Environment feature layer: \(error.localizedDescription)")
        }
        return 1.0
    }
    
    /// Maps evironment type strings to doubles
    private func envTypeToDouble(from desc: String) -> Double {
        switch desc {
        case "Städtisch (1)": return 0.0
        case "Intermediär (2)": return 1.0
        case "Ländlich (3)": return 2.0
        default: return 1.0 /// Default to rural if unknown type
        }
    }
        
    /// Uses the current weather data and converts them in an output for 1: Sunny, 2: Cloudy, 3: Rainy
    func currentWeather() async -> Double {
        /// Use cached version if available
        if let cached = cachedData, cached.isValid {
            return cached.weather
        }
        
        /// Get current location and fetch weather
        guard let point = getCurrentLocationPoint() else {
            return 2.0
        }
        
        return await currentWeather(for: point)
    }
        
    /// Fetches weather data for a specific location (used internally by caching system)
    private func currentWeather(for point: Point) async -> Double {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(point.y)&longitude=\(point.x)&current=weather_code"
        guard let url = URL(string: urlStr) else { return 2.0 }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let current = json["current"] as? [String: Any],
               let code = current["weather_code"] as? Int {
                return mapWeatherCodeToScore(code)
            }
        } catch {
            print("Weather fetch error:", error.localizedDescription)
        }
        /// Default cloudy
        return 2.0
    }
    
    /// Maps the weather code to a double
    func mapWeatherCodeToScore(_ code: Int) -> Double {
        switch code {
        case 0, 1: return 1.0 /// Sunny
        case 2, 3: return 2.0 /// Cloudy
        case 51...67, 80...99: return 3.0 /// Rain, snow, storms
        default: return 2.0   /// Cloudy as default fallback
        }
    }
        
    /// Returns the current location at call in form of a WGS84 Point geometry type
    func getCurrentLocationPoint() -> Point? {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        
        guard let userLocation = locationManager.location else {
            print("User location not available")
            return nil
        }
        let userPoint = Point(
            x: userLocation.coordinate.longitude,
            y: userLocation.coordinate.latitude,
            spatialReference: .wgs84
        )
        return userPoint
    }
    
    
    // MARK: - POI Details
    
    /// Calculates, if the POI has opening hours (1 = yes, 0=no) and if the current day and time is in the opening hours of the poi attribute, 1:is open, 0: is closed (default value)
    func isOpen(otherTags: String) -> (isOpen: Double, hasOpeningHours: Double) {
        
        /// Extract the string from opening_hours
        let tags = otherTags
            .split(separator: ",")
            .map { $0.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces) }
        
        var openingHours: String?
        for tag in tags {
            let pair = tag.split(separator: "=>", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 && pair[0] == "opening_hours" {
                openingHours = pair[1]
                break
            }
        }
        
        /// If no hours found, assume closed
        guard let hours = openingHours else { return (0.0, 0.0)}
        
        /// Parse current weekday and time
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "E"  /// Short weekday name
        let currentDay = formatter.string(from: now)
        
        formatter.dateFormat = "HH:mm"
        let currentTime = formatter.string(from: now)
        
        /// Normalize weekday to two-letter (Mo, Tu, We, etc.)
        let weekdayMap = [
            "Mon": "Mo", "Tue": "Tu", "Wed": "We", "Thu": "Th", "Fri": "Fr", "Sat": "Sa", "Sun": "Su"
        ]
        guard let normalizedDay = weekdayMap[currentDay] else { return (0.0, 1.0)}
        
        /// Check if current day & time match any defined range
        let entries = hours.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for entry in entries {
            let parts = entry.components(separatedBy: " ")

            let daysPart: String
            let timePart: String

            if parts.count == 2 {
                daysPart = parts[0]
                timePart = parts[1]
            } else if parts.count == 1 {
                /// No day range given, assume applies every day
                daysPart = "Mo-Su"
                timePart = parts[0]
            } else {
                continue
            }

            let days = daysPart.split(separator: "-")
            let validToday: Bool
            if days.count == 2 {
                let order = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                if let start = order.firstIndex(of: String(days[0])),
                   let end = order.firstIndex(of: String(days[1])),
                   let today = order.firstIndex(of: normalizedDay) {
                    validToday = start <= today && today <= end
                } else {
                    validToday = false
                }
            } else {
                validToday = String(daysPart) == normalizedDay
            }

            if validToday {
                let timeParts = timePart.split(separator: "-").map { String($0) }
                if timeParts.count == 2,
                   currentTime >= timeParts[0],
                   currentTime <= timeParts[1] {
                    return (1.0, 1.0)
                }
            }
        }
        return (0.0, 1.0)
    }
    
    /// Calculate distance between two Point geometries (handles projected coordinates)
    func calculateDistance(from point1: Point, to point2: Point) -> Double {
        /// Check if coordinates look like projected coordinates (large values)
        if abs(point1.x) > 180 || abs(point1.y) > 90 || abs(point2.x) > 180 || abs(point2.y) > 90 {
            /// These are projected coordinates, use simple Euclidean distance
            let deltaX = point1.x - point2.x
            let deltaY = point1.y - point2.y
            return sqrt(deltaX * deltaX + deltaY * deltaY)
        } else {
            /// These are lat/lon coordinates, use CLLocation
            let location1 = CLLocation(latitude: point1.y, longitude: point1.x)
            let location2 = CLLocation(latitude: point2.y, longitude: point2.x)
            return location1.distance(from: location2)
        }
    }
    
    /// Calculates the distance between the effective location and the POI Feature
    func calculateDistanceToUser(origin poi: ArcGISFeature) -> Double {
        /// Use effective location (search override or actual user location)
        guard let point = getEffectiveLocationPoint() else {
            print("No effective location available for distance calculation")
            return 360.0
        }
        
        /// Get the POI Geometry and convert into a Point Feature
        guard let poiPoint = poi.geometry as? Point else {
            print("POI geometry unavailable")
            return 360.0
        }
        
        /// Calculate distance using the effective location
        guard
            let userPoint = GeometryEngine.project(point, into: .webMercator),
            let featurePoint = GeometryEngine.project(poiPoint, into: .webMercator)
        else {
            print("Projection failed for distance calculation")
            return 360.0
        }

        let distanceMeters = GeometryEngine.distance(from: userPoint, to: featurePoint)
        let distanceKm = distanceMeters / 1000
        
        guard !distanceKm.isNaN else {
            print("Distance calculation resulted in NaN")
            return 360.0
        }
        
        return distanceKm
    }
        
    func getPOIDetails(poiID: UUID) -> (isFavorite: Double, clickCount: Double, daysAgo: Double) {
        let (fav,click,days) = DataManager.shared.getPOIInteraction(poiID: poiID, context: context)
        /// convert them into Double values for the model calculation
        let isFavorite: Double
        if fav {isFavorite = 1.0}
        else {isFavorite = 0.0}
        let clickCount: Double = Double(click)
        /// current date and time
        let now = Date()
        /// Calculate the amount of days difference and then safely convert it into a Double datatype
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: days, to: now)
        let daysAgo = Double(components.day ?? 0)
        
        return (isFavorite, clickCount, daysAgo)
    }
    
    
    // MARK: - Search Conversion

    /// Set search location override for calculations
    func setSearchLocationOverride(_ location: Point?) {
        searchLocationOverride = location
        isUsingSearchLocation = location != nil
        if let loc = location {
            print("Search location override set to: \(loc.x), \(loc.y)")
        } else {
            print("Search location override cleared")
        }
    }

    /// Get effective location (search override or actual user location)
    func getEffectiveLocationPoint() -> Point? {
        if isUsingSearchLocation, let searchLocation = searchLocationOverride {
            return searchLocation
        }
        return getCurrentLocationPoint()
    }
}
