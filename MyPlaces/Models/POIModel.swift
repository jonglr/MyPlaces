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
    
    /// Query Management attributes
    private var currentQueryTask: Task<Void, Never>?
    private var isLoading = false
    
    /// Initialization of the POI layer
    init(variableManager: VariableManager) async {
           self.variableManager = variableManager
           
           // Create ServiceFeatureTable directly
           let portalItem = PortalItem(
               portal: .arcGISOnline(connection: .authenticated),
               id: Item.ID("586c7f50dbb949188b69a3fa0e1a236d")!
           )
           
           // Create ServiceFeatureTable directly instead of through FeatureLayer
           let serviceTable = ServiceFeatureTable(item: portalItem)
           
           do {
               try await serviceTable.load()
               
               self.featureTable = serviceTable
               await loadPOIs()
           } catch {
               print("Failed to load ServiceFeatureTable: \(error)")
           }
       }
    
    /// Load Relevant POIs from the Feature Table
    func loadPOIs() async {
        await loadPOIsAroundLocation(location: nil)
    }

    /// Load POIs around a specific location (used for search results)
    func loadPOIsAroundLocation(location: Point?) async {
        // Cancel any existing query
        currentQueryTask?.cancel()
        
        // Prevent concurrent queries
        guard !isLoading else {
            print("POI loading already in progress, skipping")
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        currentQueryTask = Task {
            await performPOIQuery(location: location)
        }
        
        await currentQueryTask?.value
    }

    private func performPOIQuery(location: Point?) async {
        let userPoint: Point?
        
        if let searchLocation = location {
            userPoint = searchLocation
            print("Loading POIs around search location: \(searchLocation.x), \(searchLocation.y)")
        } else {
            userPoint = variableManager.getCurrentLocationPoint()
            guard userPoint != nil else {
                print("User location unavailable for POI loading")
                return
            }
            print("Loading POIs around user location: \(userPoint!.x), \(userPoint!.y)")
        }
        
        guard let point = userPoint else { return }
        
        /// Create a bounding box around the location
        let buffer: Double = 0.0225 // ~2.5km buffer in degrees
        let envelope = Envelope(
            xMin: point.x - buffer,
            yMin: point.y - buffer,
            xMax: point.x + buffer,
            yMax: point.y + buffer,
            spatialReference: .wgs84
        )
        
        /// Query all features within the bounding box
        do {
            // Check if task was cancelled
            guard !Task.isCancelled else {
                print("POI query was cancelled")
                return
            }
            
            let query = QueryParameters()
            query.geometry = envelope
            query.spatialRelationship = .intersects
            query.whereClause = "name IS NOT NULL AND name <> ''" // filter out unneccessary POI fetching of incomplete POIs to make the app more efficient
            
            guard let featureTable = self.featureTable else {
                print("Feature table not available")
                return
            }
            
            let result = try await featureTable.queryFeatures(using: query, queryFeatureFields: .loadAll)
            
            // Check if task was cancelled after query
            guard !Task.isCancelled else {
                print("POI query was cancelled after completion")
                return
            }
            
            let features = Array(result.features()).compactMap { $0 as? ArcGISFeature }
            
            // Update POIs on main thread
            await MainActor.run {
                self.POIs.removeAll()
                self.POIs = features
            }
            
        } catch {
            if !Task.isCancelled {
                print("Error loading POIs: \(error.localizedDescription)")
            }
        }
    }
}
