//
//  RelevanceModelManager.swift
//  MyPlaces
//
//  Created by Jon Guler on 12.04.2025.
//

/// **Class Functions**
/// Wraps the Relevance Model and outputs the Relevance Score for each POI
/// Reads and writes relevance scores to a local database or file

import CoreML

class RelevanceModelManager {
    private let model: Relevance

    init() {
        guard let loadedModel = try? Relevance(configuration: .init()) else {
            fatalError("Failed to load Relevance.mlmodel")
        }
        self.model = loadedModel
    }

    func predictRelevance(
        distance: Double,
        speed: Double,
        weather: Double,
        isOpen: Double,
        favorite: Double,
        clickCount: Double,
        lastClickedDate: Double,
        theme: Double,
        fclass: Double)
    -> Double {
        let input = RelevanceInput(
            distance: distance,
            speed: speed,
            weather: weather,
            isOpen: isOpen,
            favorite: favorite,
            clickCount: clickCount,
            lastClickedDate: lastClickedDate,
            theme: theme,
            fclass: fclass
        )
        
        do {
            let output = try model.prediction(input: input)
            return output.prediction
        } catch {
            print("Error predicting relevance: \(error.localizedDescription)")
            return 0.0 // Return a safe default value (0.0) for relevance
        }
    }
}
