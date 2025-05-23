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
            return output.classLabel
        } catch {
            print("Failed to predict theme: \(error.localizedDescription)")
            return "explore"
        }
    }
}
