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
    
    // MARK: - Initialization
    init() {
        /// Create a PortalItem of the vector basemap
        let basemapItemDay = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("56987f73d2b44570960d8a8f67bbe104")!
        )
        let irrelevantPOIItem = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("e725091c0dba4234a420736052397e2b")!
        )
        let basemapItemNight = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("f2ac67c0a5564cdc90f29585354e6163")!
        )
        /// Make a Vector Tiled Layer from the portal items
        let vtl_basemap_day = ArcGISVectorTiledLayer(item: basemapItemDay)
        let vtl_basemap_night = ArcGISVectorTiledLayer(item: basemapItemNight)
        let fl_irrelevantPOI = FeatureLayer(item: irrelevantPOIItem)
        /// Build a Basemap containing the vector tile layer
        self.basemap_day = Basemap(baseLayers: [vtl_basemap_day])
        self.basemap_night = Basemap(baseLayers: [vtl_basemap_night])
        /// Finally, create the Map
        let initialMap = Map(basemap: basemap_day)
        /// Assign it to @State variable
        self._map = State(initialValue: initialMap)
        /// Add the Irrelevant POIs as an overlay layer
        map.addOperationalLayer(fl_irrelevantPOI)
    }
    
    /// Variables for the location display & related states
    @State private var locationDisplay = LocationDisplay(dataSource: SystemLocationDataSource())
    @State private var failedToStart = false
    
    /// Variables for the pop-up logic
    @State private var identifyScreenPoint: CGPoint?
    @State private var popup: Popup? {
        didSet { showPopup = popup != nil }
    }
    @State private var showPopup = false
    @State private var floatingPanelDetent: FloatingPanelDetent = .full
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // MAP LAYER
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
                            locationDisplay.initialZoomScale = 40_000
                            locationDisplay.autoPanMode = .recenter
                        } catch {
                            self.failedToStart = true
                        }
                    }
                /// Identify the tapped feature
                    .task(id: identifyScreenPoint) {
                        guard let identifyScreenPoint else { return }
                        
                        let identifyResult = try? await proxy.identifyLayers(
                            screenPoint: identifyScreenPoint,
                            tolerance: 10,
                            returnPopupsOnly: true
                        ).first
                        
                        if let resultPopup = identifyResult?.popups.first {
                            popup = resultPopup
                            
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
                    ) {
                        if let safePopup = popup {
                            PopupView(popup: safePopup, isPresented: $showPopup)
                                .showCloseButton(true)
                                .padding()
                        } else {
                            Text("No feature found").padding()
                        }
                    }
                /// In case location fails
                    .alert("Location display failed to start", isPresented: $failedToStart) {}
                
                    .onAppear {
                        /// Build a FeatureCollectionLayer from the processed POI features
                        let fcLayer = buildFeatureCollectionLayer(from: viewModel.displayedPOIs)
                        
                        /// Add it to the map’s operational layers
                        DispatchQueue.main.async {
                            map.addOperationalLayer(fcLayer)
                        }
                    }
                    .onChange(of: settingsManager.isDarkMode) {
                        print("Dark mode changed:", settingsManager.isDarkMode)
                        map.basemap = settingsManager.isDarkMode ? basemap_night : basemap_day
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
            fields: makeFields()
        )
        let desiredNames = makeFields().map { $0.name }
        
        /// Add the [ArcGISFeature] to the collection table
        Task {
            do {
                for oldFeature in features {
                    var filteredAttributes = [String: Any]()
                    /// Filter out the attribute columns that won't be neccessary
                    for key in desiredNames {
                        if let value = oldFeature.attributes[key] {
                            filteredAttributes[key] = value
                        }
                    }
                    try await collectionTable.add(oldFeature)
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
