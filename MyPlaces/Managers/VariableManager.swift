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
            "airfield": 0.0, "airport": 1.0, "arts_centre": 2.0, "artwork": 3.0, "bakery": 4.0,
            "bar": 5.0, "beach": 6.0, "beauty_shop": 7.0, "beverages": 8.0, "bicycle_rental": 9.0,
            "bicycle_shop": 10.0, "biergarten": 11.0, "bookshop": 12.0, "bus_station": 13,
            "bus_stop": 14.0, "butcher": 15.0, "cafe": 16.0, "car_dealership": 17.0, "car_rental": 18.0,
            "chemist": 19.0, "cinema": 20.0, "clothes": 21.0, "community_centre": 22.0,
            "computer_shop": 23.0, "convenience": 24.0, "department_store": 25.0, "dog_park": 26.0,
            "doityourself": 27.0, "fast_food": 28.0, "ferry_terminal": 29.0, "florist": 30.0,
            "food_court": 31.0, "furniture_shop": 32.0, "garden_centre": 33.0, "gift_shop": 34.0,
            "greengrocer": 35.0, "hairdresser": 36.0, "helipad": 37.0, "jeweller": 38.0,
            "kiosk": 39.0, "laundry": 40.0, "mall": 41.0, "market_place": 42.0,
            "mobile_phone_shop": 43.0, "museum": 44.0, "newsagent": 45.0, "nightclub": 46.0,
            "optician": 47.0, "outdoor_shop": 48.0, "park": 49.0, "peak": 50.0,
            "picnic_site": 51.0, "pub": 52.0, "public_building": 53.0, "railway_halt": 54.0,
            "railway_station": 55.0, "restaurant": 56.0, "shoe_shop": 57.0, "sports_shop": 58.0,
            "spring": 59.0, "stationery": 60.0, "supermarket": 61.0, "taxi": 62.0,
            "theatre": 63.0, "theme_park": 64.0, "tourist_info": 65.0, "tower": 66.0,
            "town_hall": 67.0, "toy_shop": 68.0, "tram_stop": 69.0, "travel_agent": 70.0,
            "video_shop": 71.0, "viewpoint": 72.0, "wayside_shrine": 73.0, "zoo": 74.0
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
        guard let point = getCurrentLocationPoint() else {
            print("No valid user location.")
            return 1.0
        }
        print (point)
        
        do {
            let serviceItem = PortalItem(
                portal: .arcGISOnline(connection: .anonymous),
                id: Item.ID("ffcc3b01c5754a7b9e98ed3b959d73d2")!
            )
            let serviceFeatureTable = ServiceFeatureTable(item: serviceItem, layerID: 0)
            try await serviceFeatureTable.load()
            
            let queryParams = QueryParameters()
            queryParams.geometry = point
            queryParams.spatialRelationship = .intersects
            let result = try await serviceFeatureTable.queryFeatures(using: queryParams)
            
            for feature in result.features() {
                if let desc = feature.attributes["DESC_VAL"] as? String {
                    print(desc)
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
