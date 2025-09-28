//
//  ContentView.swift
//  MyPlaces
//
//  Created by Jon Guler on 27.01.2025.
//

/// **Class Functions**
/// Holds the main MapView and manages the user interactions with it (Pop-Ups and map Elements). Dynamically switches basemap themes (dark, light) based on user settings. Displays POIs with two layers: relevant (large, colored) and non-relevant (small, grey). Has Search Functionalities and User Switching and Favorite Location Storages.
/// This file is separated into different functionality topics:
/// - Variable Declaration
/// - Initialization
/// - Map View Body
/// - Map Overlay Elements
/// - Geocoding for Search
/// - Create Custom FeatureCollectionLayer
/// - Graphics for Search Results

import SwiftUI
import ArcGIS
import ArcGISToolkit
import CoreLocation


struct ContentView: View {
    
    
    // MARK: - Variable Declaration

    
    /// References to the ContentViewModel and the Managers
    @StateObject private var viewModel = ContentViewModel()
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var dataManager: DataManager
    
    /// Initialize a map variable
    @State private var map: Map
    private let basemap_day: Basemap
    private let basemap_night: Basemap
    private let basemap_outdoor: Basemap
    private let basemap_food: Basemap
    private let basemap_transportation: Basemap
    private let irrelevantPOIs: FeatureLayer
    
    /// Variables for the location display & related states
    @State private var locationDisplay = LocationDisplay(dataSource: SystemLocationDataSource())
    @State private var failedToStart = false
    
    /// Variables for the pop-up logic
    @State private var identifyScreenPoint: CGPoint?
    @State private var popup: Popup?
    @State private var showPopupSheet = false
    @State private var selectedDetent = PresentationDetent.medium
    
    /// Variables for the Theme Change
    @State private var selectedTheme: ThemeCategory = .explore
    @State private var hasSyncedTheme = false
    
    /// Variables for the Location Search
    @StateObject private var model = SearchModel()
    @State private var searchText: String = ""
    
    /// Variables for POI aggregation
    @State private var currentViewpoint: Viewpoint?
    @State private var lastKnownScale: Double = 1500
    
    @State private var layerUpdateTask: Task<Void, Never>?

    /// PopUp State Variables
    @State private var showFavoritesPanel = true
    @State private var favoritesPanelOffset: CGFloat = 0
    
    // MARK: - Initialization

    
    init() {
        /// Import the Basemap for Daytime
        let basemapItemDay = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("56987f73d2b44570960d8a8f67bbe104")!
        )
        /// Import the Basemap for Nighttime
        let basemapItemNight = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("f2ac67c0a5564cdc90f29585354e6163")!
        )
        /// Import the Basemap for Outdoor
        let basemapItemOutdoor = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("6bac1b93f52d4bce95c1236dd37c7d2b")!
        )
        /// Import the Basemap for Food theme
        let basemapItemFood = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("0a53d2c24e534826aeade132eb948fd3")!
        )
        /// Import the Basemap for Transportation theme
        let basemapItemTransportation = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("64b707b03e774df88b1aa11aded5ae7d")!
        )
        /// Convert the two items into Baseaps
        let vtl_basemap_day = ArcGISVectorTiledLayer(item: basemapItemDay)
        let vtl_basemap_night = ArcGISVectorTiledLayer(item: basemapItemNight)
        let vtl_basemap_outdoor = ArcGISVectorTiledLayer(item: basemapItemOutdoor)
        let vtl_basemap_food = ArcGISVectorTiledLayer(item: basemapItemFood)
        let vtl_basemap_transportation = ArcGISVectorTiledLayer(item: basemapItemTransportation)
        
        let basemap_day = Basemap(baseLayers: [vtl_basemap_day])
        let basemap_night = Basemap(baseLayers: [vtl_basemap_night])
        let basemap_outdoor = Basemap(baseLayers: [vtl_basemap_outdoor])
        let basemap_food = Basemap(baseLayers: [vtl_basemap_food])
        let basemap_transportation = Basemap(baseLayers: [vtl_basemap_transportation])
        
        self.basemap_day = basemap_day
        self.basemap_night = basemap_night
        self.basemap_outdoor = basemap_outdoor
        self.basemap_food = basemap_food
        self.basemap_transportation = basemap_transportation
        
        /// Get the initial theme from DataManager/SettingsManager
        let initialThemeState = DataManager.shared.fetchThemeState()
        let initialTheme = initialThemeState.userTheme ?? initialThemeState.predictedTheme ?? "explore"
            
        /// Determine the initial basemap based on the theme
        let initialBasemap: Basemap
        switch initialTheme {
        case "outdoor":
            initialBasemap = basemap_outdoor
        case "food":
            initialBasemap = basemap_food
        case "public transport":
            initialBasemap = basemap_transportation
        default:
            /// Check if it should be night mode initially
            let hour = Calendar.current.component(.hour, from: Date())
            let isNightTime = hour < 8 || hour > 19
            initialBasemap = isNightTime ? basemap_night : basemap_day
        }
            
        /// Import the irrelevant POI (grey points)
        let initialMap = Map(basemap: initialBasemap)  // Use the determined basemap
        let irrelevantPOIItem = PortalItem(
            portal: .arcGISOnline(connection: .authenticated),
            id: Item.ID("e725091c0dba4234a420736052397e2b")!
        )
        self.irrelevantPOIs = FeatureLayer(item: irrelevantPOIItem)
        initialMap.addOperationalLayer(irrelevantPOIs)
            
        /// Assign the map state variable
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
    
    
    // MARK: - Map View Body
    
    
    /// The Content View main structure
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MapViewReader { proxy in
                    ZStack {
                        /// Base map layer
                        mapLayer
                            .ignoresSafeArea(.all)
                        
                        /// UI overlays
                        VStack {
                            searchAndTogglesOverlay(proxy: proxy)  /// Pass proxy here
                            
                            /// #if DEBUG
                            /// BenchmarkTriggerView().environmentObject(viewModel)
                            /// #endif
                            
                            Spacer()
                            HStack {
                                Spacer()
                            }
                            .padding(.bottom, showFavoritesPanel ? 120 : 20)
                        }
                        /// Favorites panel
                        VStack {
                            Spacer()
                            if showFavoritesPanel {
                                FavoritesPanel(viewModel: viewModel)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .ignoresSafeArea(.all, edges: .bottom)
                    }
                }
                /// Safe area blur overlay (on top of Screen)
                VStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: geometry.safeAreaInsets.top)
                        .ignoresSafeArea(.all, edges: .top)
                    Spacer()
                }
            }
        }
        /// Relevance Score loading overlay display
        .loadingOverlay(
            isPresented: $viewModel.isComputingRelevance,
            text: "Calculating relevance scores…"
        )
        /// Popup Sheet
        .sheet(isPresented: $showPopupSheet) { [popup] in
            CustomPopupView(
                popup: popup,
                isPresented: $showPopupSheet,
                viewModel: viewModel
            )
            .presentationDetents([.medium, .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            .presentationCornerRadius(20)
        }
    }
    
    /// The Map Layer and it's logical components
    private var mapLayer: some View {
        MapViewReader { proxy in
            /// Basemap Layer
            let baseMap = MapView(
                map: map,
                graphicsOverlays: [model.graphicsOverlay]
            )
            /// Display current user location
            .locationDisplay(locationDisplay)
            
            /// Scale change observer for POI aggregation purposes
            .onViewpointChanged(kind: .centerAndScale) { newViewpoint in
                /// Update the viewpoint state
                currentViewpoint = newViewpoint
                /// Check if scale changed significantly
                let newScale = newViewpoint.targetScale
                /// Only update if scale changed by more than 10%
                let scaleChangeRatio = abs(newScale - lastKnownScale) / max(lastKnownScale, 1)
                if scaleChangeRatio > 0.1 {
                    lastKnownScale = newScale
                    /// Trigger aggregation update
                    Task {
                        await viewModel.handleMapScaleChange(newScale: newScale)
                    }
                }
            }
            
            /// Identify and localize the tap gesture on the map layer
            let withTap = baseMap
                .onSingleTapGesture { screenPoint, _ in
                    identifyScreenPoint = screenPoint
                    /// Auto-collapse favorites panel when interacting with map
                    withAnimation {
                        if showFavoritesPanel {
                            NotificationCenter.default.post(
                                name: Notification.Name("collapseFavoritesPanel"),
                                object: nil
                            )
                        }
                    }
                }
            
            /// Start location display and set the initial variables for startup (zoom/pan/center)
            let withStartTask = withTap
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
            
            /// Identify layers on tap
            let withIdentifyTask = withStartTask
                .task(id: identifyScreenPoint) {
                    guard let identifyScreenPoint,
                          let identifyResult = try? await proxy.identifyLayers(
                            screenPoint: identifyScreenPoint,
                            tolerance: 10,
                            returnPopupsOnly: true
                          ) else { return }
                    
                    if let resultPopup = identifyResult.first?.popups.first {
                        self.popup = resultPopup
                        self.showPopupSheet = self.popup != nil
                        if let feature = resultPopup.geoElement as? ArcGISFeature {
                            viewModel.recordPOIClick(poi: feature)
                            print("Feature clicked: \(feature.attributes["osm_id"] as! String)")
                        }
                    }
                }
            
            /// Alert on failure of the layer identification
            let withAlert = withIdentifyTask
                .alert("Location display failed to start", isPresented: $failedToStart) {}
            
            /// Switch Day/Night mode (with the toggle)
            let withDayNight = withAlert
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
            
            /// React to POI updates and display them newly
            let withPOIReceive = withDayNight
                .onReceive(viewModel.$displayedPOIs) { newPOIs in
                    layerUpdateTask?.cancel()
                    layerUpdateTask = Task {
                        /// debounce 0.1s
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }
                        
                        let ids: [Int64] = newPOIs.compactMap {
                            if let fid = $0.attributes["fid"] as? NSNumber {
                                return fid.int64Value
                            }
                            return nil
                        }
                        
                        let idString = ids.map { String($0) }.joined(separator: ",")
                        let definitionExpression = "fid IN (\(idString))"
                        
                        let portalItem = PortalItem(
                            portal: .arcGISOnline(connection: .authenticated),
                            id: Item.ID("586c7f50dbb949188b69a3fa0e1a236d")!
                        )
                        let filteredLayer = FeatureLayer(item: portalItem)
                        filteredLayer.definitionExpression = definitionExpression
                        
                        await MainActor.run {
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
                }
            
            /// Handle navigate-to-POI notifications for the favorites saved and clicked in the panel overlay
            let withNavigateReceive = withPOIReceive
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPOI)) { notification in
                    if let feature = notification.userInfo?["feature"] as? ArcGISFeature,
                       let geometry = feature.geometry as? Point {
                        Task {
                            await viewModel.ensurePOIVisible(feature)
                            await proxy.setViewpointCenter(geometry, scale: 800)
                            
                            /// Simulate a tap on the location of the POI to make the popup show up
                            let screenPoint = proxy.screenPoint(fromLocation: geometry)
                            if let identifyResult = try? await proxy.identifyLayers(
                                screenPoint: screenPoint ?? .init(x: 0, y: 0),
                                tolerance: 10,
                                returnPopupsOnly: true
                            ),
                               let resultPopup = identifyResult.first?.popups.first {
                                await MainActor.run {
                                    self.popup = resultPopup
                                    self.showPopupSheet = true
                                    if let identifiedFeature = resultPopup.geoElement as? ArcGISFeature {
                                        viewModel.recordPOIClick(poi: identifiedFeature)
                                    }
                                }
                            }
                        }
                    }
                }

            /// React to theme changes of the theme picker
            let withThemeChange = withNavigateReceive
                .onChange(of: settingsManager.theme) {
                    Task {
                        await viewModel.updateRelevance()
                        await viewModel.loadRelevanceScores()
                    }
                    /// Change the basemap based on the selected theme
                    DispatchQueue.main.async {
                        switch settingsManager.theme {
                        case "outdoor":
                            map.basemap = basemap_outdoor
                        case "food":
                            map.basemap = basemap_food
                        case "public transport":
                            map.basemap = basemap_transportation
                        default:
                            map.basemap = settingsManager.isNightMode ? basemap_night : basemap_day
                        }
                    }
                }

            /// Return the staged view
            let withTimeBasedTheme = withThemeChange
                .task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000) /// delay 1.5s
                    let hour = Calendar.current.component(.hour, from: Date())
                    let isNightTime = hour < 8 || hour > 19
                    await MainActor.run {
                        settingsManager.isNightMode = isNightTime   /// If its before sunrise or after sunset, the app should automatically switch between day/nightmode
                    }
                }

            return withTimeBasedTheme
        }
    }
    
    
    // MARK: - Map Overlay Elements
    
    
    private func searchAndTogglesOverlay(proxy: MapViewProxy) -> some View {
        VStack(spacing: 12) {
            /// Pill-shaped search bar
            HStack(spacing: 12) {
                /// Search Icon
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search a location...", text: $searchText)
                    .font(.system(size: 16, weight: .medium))
                
                if !searchText.isEmpty {
                    Button("Search") {
                        Task {
                            try await geocode(with: searchText, proxy: proxy)
                            searchText = "" /// Clear search text after search
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                }
                /// Add the return to user location button (blue arrow)
                Button(action: {
                    Task { @MainActor in
                        if let userPoint = viewModel.beginReturnToUserLocation() {    /// clear override, get point
                            await proxy.setViewpointCenter(userPoint, scale: 1500)     /// zoom first
                            await viewModel.completeReturnToUserLocation(userPoint)    /// then load POIs/relevance
                        }
                    }
                }) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 2)
            
            /// Theme Picker Capsule to manually change the perdicted theme afterwards
            HStack {
                Spacer()
                /// Placeholder of the actual picker
                themeSelectionPicker
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 1)
                    .onAppear {
                        /// Load effective theme from Core Data
                        let state = DataManager.shared.fetchThemeState()
                        let effective = state.userTheme ?? state.predictedTheme ?? "explore"
                        selectedTheme = ThemeCategory(rawValue: effective) ?? .explore
                        hasSyncedTheme = true
                    }
                    .onChange(of: settingsManager.theme) {
                        /// Keep picker in sync with the settings manager when theme changes externally (prediction or manually through the user - pull)
                        if let category = ThemeCategory(rawValue: settingsManager.theme) {
                            selectedTheme = category
                        }
                    }
            }
            
            /// Day & Night toggle placeholder to switch the Basemaps (bright/dark)
            HStack {
                Spacer()
                dayNightToggle
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }
    
    /// Logics of the Basemap Day&Night Toggle Switch
    private var dayNightToggle: some View {
        ZStack {
            /// Background icons
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settingsManager.isNightMode ? .secondary : .gray)
                
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settingsManager.isNightMode ? .gray : .secondary)
            }
            .padding(.horizontal, 12)
            
            /// Actual toggle on top of the symbols
            Toggle("", isOn: $settingsManager.isNightMode)
                .labelsHidden()
                .offset(x: -1)
                .toggleStyle(SwitchToggleStyle(tint: .clear))
        }
        .frame(height: 32)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 1)
    }
    
    /// Logics of the Theme Picker Menue
    private var themeSelectionPicker: some View {
        Picker("Theme", selection: $selectedTheme) {
            ForEach(ThemeCategory.allCases, id: \.self) { theme in
                Text(theme.rawValue.capitalized).tag(theme)
            }
        }
        .pickerStyle(.menu)
        /// Keep the settings manager in sync with the theme changes (push)
        .onChange(of: selectedTheme) {
            guard hasSyncedTheme else { return }
            guard settingsManager.theme != selectedTheme.rawValue else { return }
                   settingsManager.switchTheme(to: selectedTheme.rawValue)
        }
    }
    
    
    // MARK: - Geocoding for Search
    
    
    /// Maps the entered search text entered in the searchbar to a geographic location
    private func geocode(with searchText: String, proxy: MapViewProxy) async throws {
        /// Make sure the entered text is not empty
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty search text")
            return
        }
        
        /// Set the geocode parameters
        let parameters = GeocodeParameters()
        parameters.addResultAttributeName("*")
        parameters.maxResults = 1
        parameters.outputSpatialReference = .wgs84
        
        do {
            /// Fetch results from the geolocator model
            let geocodeResults = try await model.locator.geocode(forSearchText: searchText, using: parameters)
            if let firstResult = geocodeResults.first,
               let location = firstResult.displayLocation,
               let symbol = model.textGraphic.symbol as? TextSymbol {
                
                /// Project the WGS84 Locations to the search result
                let wgs84Location: Point
                            if location.spatialReference == .wgs84 {
                                wgs84Location = location
                            } else {
                                guard let projected = GeometryEngine.project(location, into: .wgs84) else {
                                    print("Failed to project coordinates to WGS84")
                                    return
                                }
                                wgs84Location = projected
                            }
                
                model.markerGraphic.geometry = location
                model.textGraphic.geometry = location
                symbol.text = firstResult.label
                
                /// Recenter map to geocoded location
                await proxy.setViewpointCenter(location, scale: 3000)
                
                /// Trigger POI reload with validated WGS84 coordinates
                await handleSearchLocationChange(searchLocation: wgs84Location)
                
                print("Search completed for: \(firstResult.label)")
            } else {
                print("No results found for search: \(searchText)")
            }
        } catch {
            print("Geocode error for '\(searchText)': \(error.localizedDescription)")
        }
    }
    
    /// Handle POI reload when map location changes through search
    private func handleSearchLocationChange(searchLocation: Point) async {
        print("Triggering POI reload for search location: \(searchLocation.x), \(searchLocation.y)")
        
        /// Notify the ContentViewModel about the new search location
        await viewModel.searchLocationChange(newLocation: searchLocation)
    }
    
    
    // MARK: - Create Custom FeatureCollectionLayer
    
    
    /// Build a custom FeatureCollection Layer of the Relevant POIs in order to add it to the map view
    private func buildFeatureCollectionLayer(from features: [ArcGISFeature]) -> FeatureCollectionLayer {
        /// Create a new FeatureCollectionTable
        let collectionTable = FeatureCollectionTable(
            fields: makeFields(),
            geometryType: Point.self,
            spatialReference: .wgs84
        )
        /// Placeholder structure for the attribute values to fit in
        let desiredNames = makeFields().map { $0.name }
        
        /// Add the [ArcGISFeature] (relevant POIs) to the collection table
        Task {
            do {
                for oldFeature in features {
                    var filteredAttributes = [String: Any]()
                    /// Fill in the values in the prepared placeholder structure
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


// MARK: - Graphics for Search Results


private class SearchModel: ObservableObject {
    
    let graphicsOverlay: GraphicsOverlay
    
    /// ArcGIS World Geolocation Service
    let locator = LocatorTask(
        url: URL(string: "https://geocode-api.arcgis.com/arcgis/rest/services/World/GeocodeServer")!
    )
    
    /// Declaration of the appearance of the located Placename as the search result
    let textGraphic: Graphic = {
        let textSymbol = TextSymbol(
            text: "",
            color: UIColor(red: 6/255.0, green: 6/255.0, blue: 7/255.0, alpha: 0.8),
            size: 25,
            horizontalAlignment: .center,
            verticalAlignment: .bottom
        )
        textSymbol.haloColor = .white
        textSymbol.haloWidth = 1
        
        return Graphic(symbol: textSymbol)
    }()
    
    /// Declaration of the appearance of the located place as a graphic (circle)
    let markerGraphic: Graphic = {
        let markerSymbol = SimpleMarkerSymbol(
            style: .circle,
            color: UIColor(red: 78/255.0, green: 143/255.0, blue: 243/255.0, alpha: 1.0),
            size: 13
        )
        return Graphic(symbol: markerSymbol)
    }()
    
    /// Assign the specifications to the class variable for the MapView to retrieve when executing a search
    init() {
        graphicsOverlay = GraphicsOverlay(graphics: [textGraphic, markerGraphic])
    }
}

