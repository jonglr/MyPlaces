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
    
    @State private var layerUpdateTask: Task<Void, Never>?
    
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

    
    /// PopUp State Variables
    @State private var showFavoritesPanel = true
    @State private var favoritesPanelOffset: CGFloat = 0
    
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
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Empty search text")
            return
        }
        
        let parameters = GeocodeParameters()
        parameters.addResultAttributeName("*")
        parameters.maxResults = 1
        parameters.outputSpatialReference = .wgs84
        
        do {
            let geocodeResults = try await model.locator.geocode(forSearchText: searchText, using: parameters)
            if let firstResult = geocodeResults.first,
               let location = firstResult.displayLocation,
               let symbol = model.textGraphic.symbol as? TextSymbol {
                
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
                
                // Trigger POI reload with validated WGS84 coordinates
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
        
        // Notify the view model about the new search location
        await viewModel.searchLocationChange(newLocation: searchLocation)
    }
    
    // MARK: - View Body
    
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
                            searchAndToggleOverlayForBody(proxy: proxy)  // Pass proxy here
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
                /// Safe area blur overlay
                VStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: geometry.safeAreaInsets.top)
                        .ignoresSafeArea(.all, edges: .top)
                    Spacer()
                }
            }
        }
        .loadingOverlay(
            isPresented: $viewModel.isComputingRelevance,
            text: "Calculating relevance scores…"
        )
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
    
    private var mapLayer: some View {
        MapViewReader { proxy in
            // Break up the long modifier chain so the compiler can type-check faster
            // by applying modifiers in stages to local variables.
            let baseMap = MapView(
                map: map,
                graphicsOverlays: [model.graphicsOverlay]
            )
            .locationDisplay(locationDisplay)
            .onViewpointChanged(kind: .centerAndScale) { newViewpoint in
                // Update the viewpoint state
                currentViewpoint = newViewpoint
                
                // Check if scale changed significantly
                let newScale = newViewpoint.targetScale
                // Only update if scale changed by more than 10%
                let scaleChangeRatio = abs(newScale - lastKnownScale) / max(lastKnownScale, 1)
                if scaleChangeRatio > 0.1 {
                    lastKnownScale = newScale
                    
                    // Trigger aggregation update
                    Task {
                        await viewModel.handleMapScaleChange(newScale: newScale)
                    }
                }
            }
            
            /// Tap gesture
            let withTap = baseMap
                .onSingleTapGesture { screenPoint, _ in
                    identifyScreenPoint = screenPoint
                    // Auto-collapse favorites panel when interacting with map
                    withAnimation {
                        if showFavoritesPanel {
                            NotificationCenter.default.post(
                                name: Notification.Name("collapseFavoritesPanel"),
                                object: nil
                            )
                        }
                    }
                }
            
            /// Start location display
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
            
            /// Alert on failure
            let withAlert = withIdentifyTask
                .alert("Location display failed to start", isPresented: $failedToStart) {}
            
            /// Switch Day/Night mode
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
            
            /// React to POI updates
            let withPOIReceive = withDayNight
                .onReceive(viewModel.$displayedPOIs) { newPOIs in
                    layerUpdateTask?.cancel()
                    layerUpdateTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // debounce 0.3s
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
                            
                            /// Simulate a tap on the location of the POI
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

            /// React to theme changes
            let withThemeChange = withNavigateReceive
                .onChange(of: settingsManager.theme) {
                    Task {
                        await viewModel.updateRelevance()
                        await viewModel.loadRelevanceScores()
                    }
                }

            /// Return the staged view
            withThemeChange
        }
    }
    
    private func searchAndToggleOverlayForBody(proxy: MapViewProxy) -> some View {
        VStack(spacing: 12) {
            // Pill-shaped search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))
                
                TextField("Search a location...", text: $searchText)
                    .font(.system(size: 16, weight: .medium))
                
                if !searchText.isEmpty {
                    Button("Search") {
                        Task {
                            try await geocode(with: searchText, proxy: proxy)
                            searchText = "" // Clear search text after search
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                }
                
                // Add the return to user location button
                Button(action: {
                    Task { @MainActor in
                        if let userPoint = viewModel.beginReturnToUserLocation() {    // clear override, get point
                            await proxy.setViewpointCenter(userPoint, scale: 1500)     // zoom first
                            await viewModel.completeReturnToUserLocation(userPoint)    // then load POIs/relevance
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
            
            HStack {
                Spacer()
                themeSelectionPicker
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 1)
                    .onAppear {
                        // Load effective theme from Core Data
                        let state = DataManager.shared.fetchThemeState()
                        let effective = state.userTheme ?? state.predictedTheme ?? "explore"
                        selectedTheme = ThemeCategory(rawValue: effective) ?? .explore
                        hasSyncedTheme = true
                    }
                    .onChange(of: settingsManager.theme) {
                        // Keep picker in sync when theme changes externally (prediction or manual)
                        if let category = ThemeCategory(rawValue: settingsManager.theme) {
                            selectedTheme = category
                        }
                    }
            }
            
            
            // Day/Night toggle below search
            HStack {
                Spacer()
                dayNightToggle
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
    }
    
    private var dayNightToggle: some View {
        ZStack {
            // Background icons
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settingsManager.isNightMode ? .secondary : .gray)
                
                Image(systemName: "moon.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(settingsManager.isNightMode ? .gray : .secondary)
            }
            .padding(.horizontal, 12)
            
            // Actual toggle
            Toggle("", isOn: $settingsManager.isNightMode)
                .labelsHidden()
                .offset(x: -1)
                .toggleStyle(SwitchToggleStyle(tint: .clear))
        }
        .frame(height: 38)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 1)
    }
    
    private var themeSelectionPicker: some View {
        Picker("Theme", selection: $selectedTheme) {
            ForEach(ThemeCategory.allCases, id: \.self) { theme in
                Text(theme.rawValue.capitalized).tag(theme)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedTheme) {
            guard hasSyncedTheme else { return }
            guard settingsManager.theme != selectedTheme.rawValue else { return }
                   settingsManager.switchTheme(to: selectedTheme.rawValue)
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
            size: 25,
            horizontalAlignment: .center,
            verticalAlignment: .bottom
        )
        
        /// Outline around text instead of background block
        textSymbol.haloColor = .white
        textSymbol.haloWidth = 1
        
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

