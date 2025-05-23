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
    
    /// Loaded POIs (ArcGISFeature Array)
    var POIs: [ArcGISFeature] = []
    
    /// Initialization of the POI layer
    init() async {
        guard let url = URL(string: featureServiceURL) else {
            fatalError("Invalid FeatureService URL")
        }
        self.featureTable = ServiceFeatureTable(url: url)
        do {
            try await self.featureTable.load()
        } catch {
            fatalError("Failed to load feature table: \(error.localizedDescription)")
        }
        await loadPOIs()
    }
    
    /// Load Relevant POIs from the Feature Table
    func loadPOIs() async {
        do {
            let query = QueryParameters()
            query.whereClause = "1=1"  // Query all features
            
            /// Directly converting the sequence of features into an array
            let result = try await featureTable.queryFeatures(using: query)
            let features = Array(result.features()).compactMap { $0 as? ArcGISFeature }
            self.POIs = features

        } catch {
            print("Error loading relevant POIs: \(error.localizedDescription)")
        }
    }
}
