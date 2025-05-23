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
    
    private let  userManager = UserProfileManager.shared
    private let dataManager = DataManager.shared
    private let context = PersistenceController.shared.container.viewContext
    
    // MARK: - Basic Conversions

    /// converts the fclasses into corresponding doubles for the model input
    func fclassConversion(fclass: String) -> Double {
        let fclassToID: [String: Double] = [
            "airfield": 0, "airport": 1, "arts_centre": 2, "artwork": 3, "bakery": 4,
            "bar": 5, "beach": 6, "beauty_shop": 7, "beverages": 8, "bicycle_rental": 9,
            "bicycle_shop": 10, "biergarten": 11, "bookshop": 12, "bus_station": 13,
            "bus_stop": 14, "butcher": 15, "cafe": 16, "car_dealership": 17, "car_rental": 18,
            "chemist": 19, "cinema": 20, "clothes": 21, "community_centre": 22,
            "computer_shop": 23, "convenience": 24, "department_store": 25, "dog_park": 26,
            "doityourself": 27, "fast_food": 28, "ferry_terminal": 29, "florist": 30,
            "food_court": 31, "furniture_shop": 32, "garden_centre": 33, "gift_shop": 34,
            "greengrocer": 35, "hairdresser": 36, "helipad": 37, "jeweller": 38,
            "kiosk": 39, "laundry": 40, "mall": 41, "market_place": 42,
            "mobile_phone_shop": 43, "museum": 44, "newsagent": 45, "nightclub": 46,
            "optician": 47, "outdoor_shop": 48, "park": 49, "peak": 50,
            "picnic_site": 51, "pub": 52, "public_building": 53, "railway_halt": 54,
            "railway_station": 55, "restaurant": 56, "shoe_shop": 57, "sports_shop": 58,
            "spring": 59, "stationery": 60, "supermarket": 61, "taxi": 62,
            "theatre": 63, "theme_park": 64, "tourist_info": 65, "tower": 66,
            "town_hall": 67, "toy_shop": 68, "tram_stop": 69, "travel_agent": 70,
            "video_shop": 71, "viewpoint": 72, "wayside_shrine": 73, "zoo": 74
        ]
        return fclassToID[fclass] ?? -1.0
    }
    
    /// Generate MD5 hash of the string (128-bit) which results in a consistant output conversion
    func createUUID(from string: String) -> UUID {
        let hash = Insecure.MD5.hash(data: string.data(using: .utf8)!)
        /// Convert the hash to Data
        let hashData = Data(hash)
        /// Extract the first 16 bytes (UUID requires 128 bits)
        let uuidBytes = hashData.prefix(16)
        /// Create a UUID from these bytes
        let uuid = uuidBytes.withUnsafeBytes { uuidBytesPointer in
            return UUID(uuid: uuidBytesPointer.load(as: uuid_t.self))
        }
        return uuid
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
            return speed * 3.6 // Convert m/s to km/h
        }
        return 0.0
    }
    
    
    // MARK: - External Information Retrieval
    
    /// Stored URL to your AGOL Feature Layer
    let featureLayerURL = URL(string: "https://services.arcgis.com/wg31rjAWgC3uC62p/arcgis/rest/services/Environment_Klassifikation/FeatureServer")!

    
    /// Maps evironment type strings to doubles
    private func envTypeToDouble(from desc: String) -> Double {
        switch desc {
        case "Städtisch (1)": return 0.0
        case "Intermediär (2)": return 1.0
        case "Ländlich (3)": return 2.0
        default: return 1.0 /// Default to rural if unknown type
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
    
    /// Fetches the context score (0 = urban, 1 = rural, 2 = nature) at the given location.
    func currentEnvironment() async -> Double {
        /// Defaults to 1.0 (rural) if no match found or an error occurs.
        guard let point = getCurrentLocationPoint() else { return 1.0 }
        
        do {
            let serviceFeatureTable = ServiceFeatureTable(url: featureLayerURL)
            
            let queryParams = QueryParameters()
            queryParams.geometry = point
            queryParams.spatialRelationship = .intersects
            queryParams.whereClause = "1=1"
            
            let result = try await serviceFeatureTable.queryFeatures(using: queryParams)
            
            for feature in result.features() {
                if let desc = feature.attributes["DESC_VAL"] as? String {
                    return envTypeToDouble(from: desc)
                }
            }
            
        } catch {
            print("Error querying Environment feature layer: \(error.localizedDescription)")
        }
        return 1.0
    }
    
    /// Uses the current weather data and converts them in an output for 1: Sunny, 2: Cloudy, 3: Rainy
    func currentWeather() async -> Double {
        guard let point = getCurrentLocationPoint() else { return 2.0 }

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

            return 2.0 /// Default: cloudy
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
    
    
    // MARK: - POI Details
    
    /// Calculates, if the current day and time is in the opening hours of the poi attribute, 1:is open, 0: is closed (default value)
    func isOpen(otherTags: String) -> Double {
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
        guard let hours = openingHours else { return 0.0 }
        
        /// Parse current weekday and time
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "E"  // Short weekday name
        let currentDay = formatter.string(from: now)
        
        formatter.dateFormat = "HH:mm"
        let currentTime = formatter.string(from: now)
        
        /// Normalize weekday to two-letter (Mo, Tu, We, etc.)
        let weekdayMap = [
            "Mon": "Mo", "Tue": "Tu", "Wed": "We", "Thu": "Th", "Fri": "Fr", "Sat": "Sa", "Sun": "Su"
        ]
        guard let normalizedDay = weekdayMap[currentDay] else { return 0.0 }
        
        /// Check if current day & time match any defined range
        let entries = hours.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for entry in entries {
            let parts = entry.components(separatedBy: " ")
            guard parts.count == 2 else { continue }
            
            let days = parts[0].split(separator: "-")
            let timeRange = parts[1]
            
            /// Check if today is in the day range
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
                validToday = String(days[0]) == normalizedDay
            }
            
            if validToday {
                let timeParts = timeRange.split(separator: "-").map { String($0) }
                if timeParts.count == 2,
                   currentTime >= timeParts[0],
                   currentTime <= timeParts[1] {
                    return 1.0
                }
            }
        }
        
        return 0.0
    }
    
    /// Calculates the distance between the current location of the user and the POI Feature
    func calculateDistance(origin poi: ArcGISFeature) -> Double {
        /// retrieve the location of the user
        guard let point = getCurrentLocationPoint() else { return 360.0 }
        /// Get the POI Geometry and convert into a Point Feature, else return the max kilometer distance of the model training dataset
        guard let poi = poi.geometry as? Point else { return 360.0 }
        /// Calculate the distance between
        let distanceMeters = GeometryEngine.distance(from: point, to: poi)
        /// Return the distance in Kiolometeres
        return distanceMeters / 1000.0
    }
        
    func getPOIDetails(poiID: UUID) -> (isFavorite: Double, clickCount: Double, daysAgo: Double) {
        let (fav,click,days) = DataManager.shared.getPOIInteractionDetails(poiID: poiID, context: context)
        /// convert them into Double values for the model calculation
        let isFavorite: Double
        if fav {isFavorite = 1.0}
        else {isFavorite = 0.0}
        
        let clickCount: Double = Double(click)
        
        let now = Date()  // current date and time
        /// Calculate the amount of days difference and then safely convert it into a Double datatype
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: days, to: now)
        let daysAgo = Double(components.day ?? 0)
        
        return (isFavorite, clickCount, daysAgo)
    }
        
}
