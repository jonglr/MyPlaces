//
//  PerformanceMonitor.swift
//  MyPlaces
//
//  Created by Jon Guler on 6.09.2025.
//

///**Class Functions**
/// Measures and safes the app performance scores
///  Activate it in the ContentView at line 144-146

import Foundation
import ArcGIS
import CoreLocation
import SwiftUI

// MARK: - Performance Collector

class PerformanceCollector: ObservableObject {
    static let shared = PerformanceCollector()
    
    /// Data storage
    private var measurements: [PerformanceMeasurement] = []
    private let dateFormatter = ISO8601DateFormatter()
    
    struct PerformanceMeasurement {
        let timestamp: Date
        let poiCount: Int
        let environment: String  /// urban, rural, outdoor
        let relevanceTime: TimeInterval
        let thematicTime: TimeInterval
        let aggregationTime: TimeInterval
        let poiLoadingTime: TimeInterval
        let displayedPOIs: Int
        let reductionRate: Double
        let scale: Double
        
        var totalTime: TimeInterval {
            relevanceTime + thematicTime + aggregationTime + poiLoadingTime
        }
        
        var relevancePerPOI: TimeInterval {
            poiCount > 0 ? relevanceTime / Double(poiCount) * 1000 : 0 // ms
        }
        
        /// CSV header
        static var csvHeader: String {
            "timestamp,environment,poi_count,displayed_pois,reduction_rate,scale,relevance_time_ms,thematic_time_ms,aggregation_time_ms,loading_time_ms,total_time_ms,relevance_per_poi_ms"
        }
        
        /// CSV row
        var csvRow: String {
            let formatter = ISO8601DateFormatter()
            return "\(formatter.string(from: timestamp)),\(environment),\(poiCount),\(displayedPOIs),\(String(format: "%.2f", reductionRate)),\(String(format: "%.0f", scale)),\(String(format: "%.2f", relevanceTime * 1000)),\(String(format: "%.2f", thematicTime * 1000)),\(String(format: "%.2f", aggregationTime * 1000)),\(String(format: "%.2f", poiLoadingTime * 1000)),\(String(format: "%.2f", totalTime * 1000)),\(String(format: "%.3f", relevancePerPOI))"
        }
    }
    
    /// Temporary storage for ongoing measurement
    private var currentMeasurement: CurrentMeasurement = CurrentMeasurement()
    
    private struct CurrentMeasurement {
        var poiCount: Int = 0
        var environment: String = "unknown"
        var relevanceTime: TimeInterval = 0
        var thematicTime: TimeInterval = 0
        var aggregationTime: TimeInterval = 0
        var poiLoadingTime: TimeInterval = 0
        var displayedPOIs: Int = 0
        var scale: Double = 1500
        
        mutating func reset() {
            poiCount = 0
            environment = "unknown"
            relevanceTime = 0
            thematicTime = 0
            aggregationTime = 0
            poiLoadingTime = 0
            displayedPOIs = 0
            scale = 1500
        }
    }
    
    // MARK: - Recording Methods
    
    func recordRelevanceScoring(time: TimeInterval, poiCount: Int) {
        currentMeasurement.relevanceTime = time
        currentMeasurement.poiCount = poiCount
        print("Relevance: \(time * 1000)ms for \(poiCount) POIs")
    }
    
    func recordThematicPrediction(time: TimeInterval) {
        currentMeasurement.thematicTime = time
        print("Thematic: \(time * 1000)ms")
    }
    
    func recordAggregation(time: TimeInterval, beforeCount: Int, afterCount: Int) {
        currentMeasurement.aggregationTime = time
        currentMeasurement.displayedPOIs = afterCount
        print("Aggregation: \(time * 1000)ms | \(beforeCount) → \(afterCount)")
    }
    
    func recordPOILoading(time: TimeInterval) {
        currentMeasurement.poiLoadingTime = time
        print("POI Loading: \(time * 1000)ms")
    }
    
    func setEnvironment(_ environment: String) {
        currentMeasurement.environment = environment
    }
    
    func setScale(_ scale: Double) {
        currentMeasurement.scale = scale
    }
    
    /// Complete a measurement cycle
    func completeMeasurement() {
        let reductionRate = currentMeasurement.poiCount > 0
            ? Double(currentMeasurement.poiCount - currentMeasurement.displayedPOIs) / Double(currentMeasurement.poiCount)
            : 0
        
        let measurement = PerformanceMeasurement(
            timestamp: Date(),
            poiCount: currentMeasurement.poiCount,
            environment: currentMeasurement.environment,
            relevanceTime: currentMeasurement.relevanceTime,
            thematicTime: currentMeasurement.thematicTime,
            aggregationTime: currentMeasurement.aggregationTime,
            poiLoadingTime: currentMeasurement.poiLoadingTime,
            displayedPOIs: currentMeasurement.displayedPOIs,
            reductionRate: reductionRate,
            scale: currentMeasurement.scale
        )
        
        measurements.append(measurement)
        currentMeasurement.reset()
        
        print("""
        --------------------------------------------
        MEASUREMENT #\(measurements.count) COMPLETED
        --------------------------------------------
        Environment:    \(measurement.environment)
        POIs:          \(measurement.poiCount) → \(measurement.displayedPOIs) (\(String(format: "%.1f", reductionRate * 100))% reduction)
        Scale:         \(String(format: "%.0f", measurement.scale))
        --------------------------------------------
        Relevance:     \(String(format: "%.2f", measurement.relevanceTime * 1000))ms (\(String(format: "%.3f", measurement.relevancePerPOI))ms/POI)
        Thematic:      \(String(format: "%.2f", measurement.thematicTime * 1000))ms
        Aggregation:   \(String(format: "%.2f", measurement.aggregationTime * 1000))ms
        POI Loading:   \(String(format: "%.2f", measurement.poiLoadingTime * 1000))ms
        --------------------------------------------
        TOTAL:         \(String(format: "%.2f", measurement.totalTime * 1000))ms
        --------------------------------------------        
        """)
    }
    
    // MARK: - Export Methods
    
    /// Export data as CSV
    func exportToCSV() -> String {
        var csv = PerformanceMeasurement.csvHeader + "\n"
        for measurement in measurements {
            csv += measurement.csvRow + "\n"
        }
        return csv
    }
    
    /// Save CSV to Documents directory
    func saveCSVToDocuments(filename: String = "performance_data") {
        let csv = exportToCSV()
        let fileName = "\(filename)_\(Date().timeIntervalSince1970).csv"
        
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsPath.appendingPathComponent(fileName)
            
            do {
                try csv.write(to: fileURL, atomically: true, encoding: .utf8)
                print("CSV saved to: \(fileURL.path)")
                print("File access through Xcode: Window → Devices and Simulators → Select Device → Select App → Download Container")
            } catch {
                print("Failed to save CSV: \(error)")
            }
        }
    }
}

// MARK: - Integration with ContentViewModel

extension ContentViewModel {
    
    @MainActor
    /// Run a comprehensive benchmark test
    func runThesisBenchmark() async {
        let collector = PerformanceCollector.shared
        
        print("STARTING THESIS PERFORMANCE COLLECTOR")
        
        /// Test scenarios
        let scenarios: [(env: String, location: CLLocationCoordinate2D, scales: [Double])] = [
            ("urban", CLLocationCoordinate2D(latitude: 47.367101, longitude: 8.544993), [500, 1500, 5000]),  /// Zurich
            ("rural", CLLocationCoordinate2D(latitude: 47.252291, longitude: 8.767640), [500, 1500, 5000]), /// Hombrechtikon
            ("outdoor", CLLocationCoordinate2D(latitude: 47.256108, longitude: 9.318799), [500, 1500, 5000]) /// Schwägalp
        ]
        
        for scenario in scenarios {
            for scale in scenario.scales {
                self.unfilteredRelevantPOIs.removeAll()
                self.displayedPOIs.removeAll()
                
                print("\nTesting: \(scenario.env.uppercased()) at scale \(scale)")
                
                collector.setEnvironment(scenario.env)
                collector.setScale(scale)
                
                /// Simulate location change
                let location = Point(x: scenario.location.longitude,
                                    y: scenario.location.latitude,
                                    spatialReference: .wgs84)
                
                /// Set virutal location
                variableManager.setSearchLocationOverride(location)
                self.isUsingSearchLocation = true
                self.currentSearchLocation = location
                
                /// POI Loading
                let loadStart = CFAbsoluteTimeGetCurrent()
                await reloadPOIsForLocation(location)
                collector.recordPOILoading(time: CFAbsoluteTimeGetCurrent() - loadStart)
                
                /// Theme Prediction
                let themeStart = CFAbsoluteTimeGetCurrent()
                await updateTheme()
                collector.recordThematicPrediction(time: CFAbsoluteTimeGetCurrent() - themeStart)
                
                /// Relevance Scoring
                let relevanceStart = CFAbsoluteTimeGetCurrent()
                await updateRelevance()
                collector.recordRelevanceScoring(
                    time: CFAbsoluteTimeGetCurrent() - relevanceStart,
                    poiCount: allPOIs.count
                )

                /// Aggregation (measure and capture displayed POIs)
                let aggStart = CFAbsoluteTimeGetCurrent()
                self.currentMapScale = scale   /// apply scenario scale
                self.lastAggregationScale = 0  /// force re-aggregation

                await loadRelevanceScores()  /// this should populate displayedPOIs
                let beforeCount = allPOIs.count
                
                await quickReaggregate()       /// rebuild displayed list using current scale
                let afterCount = displayedPOIs.count
                
                collector.recordAggregation(
                    time: CFAbsoluteTimeGetCurrent() - aggStart,
                    beforeCount: beforeCount,
                    afterCount: afterCount
                )
                
                /// Complete this measurement
                collector.completeMeasurement()
                
                /// Small delay between tests
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        /// Export results
        collector.saveCSVToDocuments()
    }
}

// MARK: - Simple Benchmark Trigger

#if DEBUG
struct BenchmarkTriggerView: View {
    @State private var isRunning = false
    @State private var showResults = false
    @EnvironmentObject var viewModel: ContentViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Button(action: runBenchmark) {
                Label(isRunning ? "Running Benchmark..." : "Run Thesis Benchmark",
                      systemImage: "chart.line.uptrend.xyaxis")
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isRunning)
            
            if showResults {
                Button("Export CSV") {
                    PerformanceCollector.shared.saveCSVToDocuments()
                }
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
    }
    
    private func runBenchmark() {
        isRunning = true
        showResults = false
        
        Task {
            await viewModel.runThesisBenchmark()
            
            isRunning = false
            showResults = true
        }
    }
}
#endif
