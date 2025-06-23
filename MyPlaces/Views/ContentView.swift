//
//  ContentView.swift
//  MyPlaces
//
//  Created by Jon Guler on 27.01.2025.
//

/// **Class Functions**
/// Manages the primary MapView and its interactions (Pop-Ups and map Elements)
/// Dynamically switches basemap themes (dark, light) based on user settings.
/// Displays POIs with two layers: relevant (large, colored) and non-relevant (small, grey).

import SwiftUI
import ArcGIS
import ArcGISToolkit
import CoreLocation

struct ContentView: View {
    
    /// Keep a reference to the ContentViewModel
    @StateObject private var viewModel = ContentViewModel()
    @EnvironmentObject var settingsManager: SettingsManager
    
    /// Initialize a map variable
    @State private var map: Map
    private let basemap_day: Basemap
    private let basemap_night: Basemap
    private let irrelevantPOIs: FeatureLayer
    
    // MARK: - Initialization
    init() {
        let basemapItemDay = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("56987f73d2b44570960d8a8f67bbe104")!
        )
        let basemapItemNight = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("f2ac67c0a5564cdc90f29585354e6163")!
        )
        let vtl_basemap_day = ArcGISVectorTiledLayer(item: basemapItemDay)
        let vtl_basemap_night = ArcGISVectorTiledLayer(item: basemapItemNight)
        let basemap_day = Basemap(baseLayers: [vtl_basemap_day])
        let basemap_night = Basemap(baseLayers: [vtl_basemap_night])
        self.basemap_day = basemap_day
        self.basemap_night = basemap_night

        let initialMap = Map(basemap: basemap_day)
        let irrelevantPOIItem = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("e725091c0dba4234a420736052397e2b")!
        )
        self.irrelevantPOIs = FeatureLayer(item: irrelevantPOIItem)
        initialMap.addOperationalLayer(irrelevantPOIs)
        
        self._map = State(initialValue: initialMap)
    }
    
    private func createMap(using basemap: Basemap) -> Map {
        let map = Map(basemap: basemap)
        map.addOperationalLayer(self.irrelevantPOIs)
        return map
    }
    
    /// Variables for the location display & related states
    @State private var locationDisplay = LocationDisplay(dataSource: SystemLocationDataSource())
    @State private var failedToStart = false
    
    /// Variables for the pop-up logic
    @State private var identifyScreenPoint: CGPoint?
    @State private var popup: Popup?
    @State private var showPopup = false
    @State private var floatingPanelDetent: FloatingPanelDetent = .full
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapViewReader { proxy in
                MapView(map: map)
                    .locationDisplay(locationDisplay)
                
                /// Single tap gesture to identify layers
                    .onSingleTapGesture { screenPoint, _ in
                        identifyScreenPoint = screenPoint
                    }
                
                /// Start location display
                    .task {
                        let locationManager = CLLocationManager()
                        if locationManager.authorizationStatus == .notDetermined {
                            locationManager.requestWhenInUseAuthorization()
                        }
                        do {
                            try await locationDisplay.dataSource.start()
                            locationDisplay.initialZoomScale = 10_000
                            locationDisplay.autoPanMode = .recenter
                        } catch {
                            self.failedToStart = true
                        }
                    }
                /// Identify the tapped feature
                    .task(id: identifyScreenPoint) {
                        guard let identifyScreenPoint,
                              let identifyResult = try? await proxy.identifyLayers(
                                screenPoint: identifyScreenPoint,
                                tolerance: 10,
                                returnPopupsOnly: true
                              ) else { return }
                        
                        if let resultPopup = identifyResult.first?.popups.first {
                            self.popup = resultPopup
                            self.showPopup = self.popup != nil
                            /// Extract the ArcGIS feature and record a click
                            if let feature = resultPopup.geoElement as? ArcGISFeature {
                                viewModel.recordPOIClick(poi: feature)
                                print("Feature clicked: \(feature.attributes["osm_id"] as! String)")
                            }
                        }
                    }
                /// Floating panel for pop-ups
                    .floatingPanel(
                        selectedDetent: $floatingPanelDetent,
                        horizontalAlignment: .leading,
                        isPresented: $showPopup
                    ) { [popup] in
                        PopupView(popup: popup!, isPresented: $showPopup)
                            .showCloseButton(true)
                            .padding()
                    }
                /// In case location fails
                    .alert("Location display failed to start", isPresented: $failedToStart) {}
                
                    .onChange(of: settingsManager.isDarkMode) {
                        map = createMap(using: settingsManager.isDarkMode ? basemap_night : basemap_day)
                    }
                    .onReceive(viewModel.$displayedPOIs) { newPOIs in
                        // Extract the IDs of the relevant POIs
                        let ids: [Int64] = newPOIs.compactMap {
                            if let fid = $0.attributes["fid"] as? NSNumber {
                                return fid.int64Value
                            }
                            return nil
                        }

                        // Convert the list of IDs into a comma-separated string
                        let idString = ids.map { String($0) }.joined(separator: ",")
                        let definitionExpression = "fid IN (\(idString))"
                        
                        // Define the ID of the filtered POI layer to track
                        let filteredPOIItemID = Item.ID("586c7f50dbb949188b69a3fa0e1a236d")!

                        // Load the original layer from ArcGIS Online
                        let portalItem = PortalItem(
                            portal: .arcGISOnline(connection: .authenticated),
                            id: Item.ID("586c7f50dbb949188b69a3fa0e1a236d")!
                        )
                        let filteredLayer = FeatureLayer(item: portalItem)

                        // Apply the filter
                        filteredLayer.definitionExpression = definitionExpression

                        // Remove any existing filtered layers
                        DispatchQueue.main.async {
                            for layer in map.operationalLayers {
                                if let fl = layer as? FeatureLayer,
                                   let existingItemID = fl.item?.id,
                                   existingItemID == filteredPOIItemID {
                                    map.removeOperationalLayer(fl)
                                }
                            }
                            map.addOperationalLayer(filteredLayer)
                        }
                    }
            }
            // TOGGLE OVERLAY
            Toggle(isOn: $settingsManager.isDarkMode) {
                Image(systemName: settingsManager.isDarkMode ? "moon.fill" : "sun.max.fill")
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
            .padding()
        }
    }
}
    
    // MARK: - Build a FeatureCollectionLayer from filtered POIs
    
    private func buildFeatureCollectionLayer(from features: [ArcGISFeature]) -> FeatureCollectionLayer {
        /// Create a new FeatureCollectionTable
        let collectionTable = FeatureCollectionTable(
            fields: makeFields(),
            geometryType: Point.self,
            spatialReference: .wgs84
        )
        let desiredNames = makeFields().map { $0.name }
        
        /// Add the [ArcGISFeature] to the collection table
        Task {
            do {
                for oldFeature in features {
                    var filteredAttributes = [String: Any]()
                    for key in desiredNames {
                        if let value = oldFeature.attributes[key] {
                            filteredAttributes[key] = value
                        }
                    }
                    let newFeature = collectionTable.makeFeature(attributes: filteredAttributes, geometry: oldFeature.geometry)
                    try await collectionTable.add(newFeature)
                }
            } catch {
                print("Failed adding rows: \(error)")
            }
        }
        
        /// Wrap in a FeatureCollection, then a FeatureCollectionLayer
        let collection = FeatureCollection(featureCollectionTables: [collectionTable])
        let fcLayer = FeatureCollectionLayer(featureCollection: collection)
        
        return fcLayer
    }
    
    // MARK: - Dynamically create fields from the first feature's attributes
    
    /// Dynamically creates [Field] from the feature's attributes.
    private func makeFields() -> [Field] {
        return [
            Field(type: .text, name: "osm_id",     alias: "osm_id"),
            Field(type: .int32, name: "code",     alias: "code"),
            Field(type: .text, name: "fclass",     alias: "fclass"),
            Field(type: .text, name: "name",       alias: "name"),
            Field(type: .text, name: "address",    alias: "address"),
            Field(type: .text, name: "other_tags", alias: "other_tags")
        ]
    }
