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

// MARK: - Graphics for Search

private class SearchModel: ObservableObject {
    
    let graphicsOverlay: GraphicsOverlay
    
    let locator = LocatorTask(
        url: URL(string: "https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer")!
    )
    let textGraphic: Graphic = {
        let textSymbol = TextSymbol(
            text: "",
            color: UIColor(red: 6/255.0, green: 6/255.0, blue: 7/255.0, alpha: 0.8),
            size: 19,
            horizontalAlignment: .center,
            verticalAlignment: .bottom
        )
        
        /// Outline around text instead of background block
        textSymbol.haloColor = .white
        textSymbol.haloWidth = 1.5
        
        return Graphic(symbol: textSymbol)
    }()
    
    let markerGraphic: Graphic = {
        let markerSymbol = SimpleMarkerSymbol(
            style: .circle,
            color: UIColor(red: 78/255.0, green: 143/255.0, blue: 243/255.0, alpha: 1.0),
            size: 13
        )
        return Graphic(symbol: markerSymbol)
    }()
    
    init() {
        graphicsOverlay = GraphicsOverlay(graphics: [textGraphic, markerGraphic])
    }
}


struct ContentView: View {
    
    // MARK: - Initialization
    
    /// Keep a reference to the ContentViewModel
    @StateObject private var viewModel = ContentViewModel()
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var dataManager: DataManager
    
    /// Initialize a map variable
    @State private var map: Map
    private let basemap_day: Basemap
    private let basemap_night: Basemap
    private let irrelevantPOIs: FeatureLayer
    
    /// Variables for the location display & related states
    @State private var locationDisplay = LocationDisplay(dataSource: SystemLocationDataSource())
    @State private var failedToStart = false
    
    /// Variables for the pop-up logic
    @State private var identifyScreenPoint: CGPoint?
    @State private var popup: Popup?
    @State private var showPopup = false
    @State private var floatingPanelDetent: FloatingPanelDetent = .half
    
    @State private var selectedTheme: ThemeCategory = .explore
    
    @StateObject private var model = SearchModel()
    @State private var searchText: String = ""
    
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
    
    /// Possible themes for the theme picker element
    enum ThemeCategory: String, CaseIterable, Identifiable {
        var id: String { self.rawValue }
        
        case culture
        case explore
        case food
        case outdoor
        case publicTransport = "public transport"
        case shopping
    }
    
    // MARK: - Geocode Function
    
    private func geocode(with searchText: String, proxy: MapViewProxy) async throws {
        let parameters = GeocodeParameters()
        parameters.addResultAttributeName("*")
        parameters.maxResults = 1
        parameters.outputSpatialReference = map.spatialReference
        
        let geocodeResults = try await model.locator.geocode(forSearchText: searchText, using: parameters)
        if let firstResult = geocodeResults.first,
           let location = firstResult.displayLocation,
           let symbol = model.textGraphic.symbol as? TextSymbol {
            
            model.markerGraphic.geometry = location
            model.textGraphic.geometry = location
            symbol.text = firstResult.label
            
            /// Recenter map to current user location instead of geocode location
            await proxy.setViewpointCenter(location, scale: 5000)
        }
    }
    
    // MARK: - View Body
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            mapLayer
            toggleOverlay
            themePicker
        }
        .loadingOverlay(
                    isPresented: $viewModel.isComputingRelevance,
                    text: "Calculating relevance scores…"
        )
    }
    
    private var mapLayer: some View {
        MapViewReader { proxy in
            ZStack(alignment: .topTrailing) {
                MapView(
                    map: map,
                    graphicsOverlays: [model.graphicsOverlay]
                )
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
                            locationDisplay.initialZoomScale = 1_500
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
                                print("Relevance Score of POI Feature: ", viewModel.getRelevanceScore(for: feature))
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
                    
                    /// Switch Day/Nightmode
                    .onChange(of: settingsManager.isNightMode) {
                        print("Switching to \(settingsManager.isNightMode ? "night" : "day") mode")
                        
                        DispatchQueue.main.async {
                            if settingsManager.isNightMode {
                                let nightItem = PortalItem(
                                    portal: .arcGISOnline(connection: .authenticated),
                                    id: Item.ID("f2ac67c0a5564cdc90f29585354e6163")!
                                )
                                let nightLayer = ArcGISVectorTiledLayer(item: nightItem)
                                map.basemap = Basemap(baseLayers: [nightLayer])
                            } else {
                                let dayItem = PortalItem(
                                    portal: .arcGISOnline(connection: .authenticated),
                                    id: Item.ID("56987f73d2b44570960d8a8f67bbe104")!
                                )
                                let dayLayer = ArcGISVectorTiledLayer(item: dayItem)
                                map.basemap = Basemap(baseLayers: [dayLayer])
                            }
                        }
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
                                   existingItemID == portalItem.id {
                                    map.removeOperationalLayer(fl)
                                }
                            }
                            map.addOperationalLayer(filteredLayer)
                        }
                    }
                    .onChange(of: settingsManager.theme) {
                        Task {
                            await viewModel.updateRelevance()
                            await viewModel.loadRelevanceScores()
                        }
                    }
                
                VStack {
                    HStack {
                        TextField("Enter address", text: $searchText)
                        Spacer()
                        Button("Search") {
                            Task {
                                try await geocode(with: searchText, proxy: proxy)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 60, leading: 10, bottom: 10, trailing: 10))
                    .background(.thinMaterial, ignoresSafeAreaEdges: .horizontal)
                    
                    Spacer()
                }
            }
        }
    }
    
    private var toggleOverlay: some View {
        HStack {
            Spacer()
            ZStack {
                /// Background icons
                HStack {
                    Image(systemName: "sun.max.fill")
                        .scaleEffect(0.7)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "moon.fill")
                        .scaleEffect(0.7)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                
                /// Actual toggle
                Toggle("", isOn: $settingsManager.isNightMode)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .clear))
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // Full overlay
            }
            .frame(width: 50, height: 30) // Match this height to Toggle's actual size
            .background(.thinMaterial)
            .cornerRadius(16)
            .padding(.top, 16)
            .padding(.trailing, 16)
            .clipped() // Ensure content stays within corners
        }
    }
    
    private var themeSelectionPicker: some View {
        Picker("Theme", selection: $selectedTheme) {
            ForEach(ThemeCategory.allCases) { theme in
                Text(theme.rawValue.capitalized)
                    .tag(theme)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedTheme) {
            settingsManager.switchTheme(to: selectedTheme.rawValue)
        }
    }
    
    private var themePicker: some View {
        VStack {
            Spacer()
            HStack {
                Text("Theme:")
                    .foregroundColor(.white)
                
                themeSelectionPicker
                    .padding(8)
                    .background(.thinMaterial)
                    .cornerRadius(8)
            }
            .padding()
        }
        .onAppear {
            /// Sync with the latest theme from settingsManager
            if let currentTheme = dataManager.fetchTheme(),
               let category = ThemeCategory(rawValue: currentTheme) {
                selectedTheme = category
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
}
