//
//  ThematicModelManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 12.04.2025.
//

/// **Class Functions**
/// Wraps the Thematic Model and outputs the Thematic Choice

import CoreML

class ThematicModelManager {
    private let model: Thematic
    private let themeLookup: [Int: String] = [
        0: "shopping",
        1: "food",
        2: "public transport",
        3: "culture",
        4: "outdoor",
        5: "explore"
    ]
    
    init() {
        guard let loadedModel = try? Thematic(configuration: .init()) else {
            fatalError("Failed to load Thematic.mlmodel")
        }
        self.model = loadedModel
    }

    func predictTheme(timeOfDay: Double, dayOfWeek: Double, environmentType: Double) -> String {
        let input = ThematicInput(environmentType: environmentType, timeOfDay: timeOfDay, dayOfWeek: dayOfWeek)
        do {
            let output = try model.prediction(input: input)
            
            /// Convert the integer output to the corresponding theme string
            let themeIndex = Int(output.themeLabel) // Assuming themeLabel is a number
            print ("AAAAAAAAAAAAA \(themeIndex)")
            return themeLookup[themeIndex] ?? "explore" // Return "explore" as fallback
            
        } catch {
            print("Failed to predict theme: \(error.localizedDescription)")
            return "explore"
        }
    }
}
