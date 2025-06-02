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
    
    /// The URL to the POI Feature Layers
    private let featureServiceURL = "https://services.arcgis.com/wg31rjAWgC3uC62p/arcgis/rest/services/OSM_POI/FeatureServer/0"
    /// The feature table to query
    private var featureTable: ServiceFeatureTable
    private let variableManager: VariableManager
    /// Loaded POIs (ArcGISFeature Array)
    var POIs: [ArcGISFeature] = []
    
    /// Initialization of the POI layer
    init(variableManager: VariableManager) async {
        self.variableManager = variableManager
        guard let url = URL(string: featureServiceURL) else {
            fatalError("Invalid FeatureService URL for POIs")
        }
        self.featureTable = ServiceFeatureTable(url: url)
        do {
            try await self.featureTable.load()
        } catch {
            fatalError("Failed to load feature table for POIs: \(error.localizedDescription)")
        }
        await loadPOIs()
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
            let result = try await featureTable.queryFeatures(using: query)
            let features = Array(result.features()).compactMap { $0 as? ArcGISFeature }
            self.POIs = features
            print("Loaded \(features.count) POIs near user")
        } catch {
            print("Error loading relevant POIs: \(error.localizedDescription)")
        }
    }
}
