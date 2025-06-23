//
//  POIModel.swift
//  MyPlaces
//
//  Created by Jon Guler on 12.04.2025.
//

/// **Class Functions**
/// Takes the Hosted POI Feature Layer from ArcGIS Online and reprensents the data as a ArcGIS Feature array

import ArcGIS
import Foundation
import SwiftUI

class POIModel {
    
    /// The feature table to query
    private var featureTable: ServiceFeatureTable?
    private let variableManager: VariableManager
    /// Loaded POIs (ArcGISFeaturef Array)
    var POIs: [ArcGISFeature] = []
    
    /// Initialization of the POI layer
    init(variableManager: VariableManager) async {
        self.variableManager = variableManager
        do {
            let portalItem = PortalItem(
                portal: .arcGISOnline(connection: .authenticated),
                id: Item.ID("586c7f50dbb949188b69a3fa0e1a236d")!
            )
            let featureLayer = FeatureLayer(item: portalItem)
            /// Load th Feature Layer to have all the attributes available
            do {
                try await featureLayer.load()
            } catch {
                print("Failed to load Feature Layer of POIs: \(error)")
            }
            if let table = featureLayer.featureTable as? ServiceFeatureTable {
                self.featureTable = table
                await loadPOIs()
            } else {
                print("Feature table of the POIs could not be cast.")
            }
        }
    }
    
    /// Load Relevant POIs from the Feature Table
    func loadPOIs() async {
        guard let userPoint = variableManager.getCurrentLocationPoint() else {
            print("User location unavailable for POI loading")
            return
        }
        
        /// Create a bounding box around the user location
        let buffer: Double = 0.01 // ~1km buffer in degrees
        let envelope = Envelope(
            xMin: userPoint.x - buffer,
            yMin: userPoint.y - buffer,
            xMax: userPoint.x + buffer,
            yMax: userPoint.y + buffer,
            spatialReference: .wgs84
        )
        
        /// Query all features within the bounding box around the user's location
        do {
            let query = QueryParameters()
            query.geometry = envelope
            query.spatialRelationship = .intersects
            query.whereClause = "1=1"
            
            /// Directly converting the sequence of features into an array
            guard let featureTable = self.featureTable else { return }
            /// Query the feature table and store retrieve all the attribute fields
            let result = try await featureTable.queryFeatures(using: query, queryFeatureFields: .loadAll)
            /// Convert the Query result to an array of ArcGISFeatures
            let features = Array(result.features()).compactMap { $0 as? ArcGISFeature }
            self.POIs = features
            print("Loaded \(features.count) POIs near user")
        } catch {
            print("Error loading relevant POIs: \(error.localizedDescription)")
        }
    }
}
