//
//  HeatmapView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 26/10/2025.
//


import SwiftUI
import MapKit

struct HeatmapView: View {
    @StateObject private var storage = SessionStorage.shared
    @StateObject private var mapStyleManager = MapStyleManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var heatmapData: [HeatmapPoint] = []
    @State private var selectedIntensity: HeatmapIntensity = .medium
    @State private var showingSettings = false
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map with heatmap overlay
                Map(position: $cameraPosition) {
                    // Draw heatmap circles for each point
                    ForEach(heatmapData) { point in
                        MapCircle(center: point.coordinate, radius: point.radius)
                            .foregroundStyle(point.color.opacity(point.opacity))
                    }
                    
                    // Show actual dwell markers on top
                    ForEach(getAllDwells(), id: \.id) { dwell in
                        Annotation("", coordinate: dwell.location) {
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(.purple, lineWidth: 2)
                                )
                        }
                    }
                }
                .mapStyle(mapStyleManager.getMapStyle())
                
                // Stats overlay at top
                VStack {
                    statsCard()
                        .padding()
                    Spacer()
                }
                
                // Intensity selector at bottom
                VStack {
                    Spacer()
                    intensitySelector()
                        .padding()
                }
                
                if isLoading {
                    loadingOverlay()
                }
            }
            .navigationTitle("Heatmap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                HeatmapSettingsView(
                    selectedIntensity: $selectedIntensity,
                    onApply: {
                        generateHeatmap()
                    }
                )
                .presentationDetents([.medium])
            }
            .onAppear {
                setupInitialView()
            }
        }
    }
    
    // MARK: - Stats Card
    
    @ViewBuilder
    private func statsCard() -> some View {
        HStack(spacing: 20) {
            statItem(
                icon: "flame.fill",
                label: "Hot Spots",
                value: "\(getHotSpots().count)",
                color: .orange
            )
            
            Divider()
                .frame(height: 40)
            
            statItem(
                icon: "mappin.circle.fill",
                label: "Total Stops",
                value: "\(getAllDwells().count)",
                color: .purple
            )
            
            Divider()
                .frame(height: 40)
            
            statItem(
                icon: "moon.stars.fill",
                label: "Nights",
                value: "\(storage.sessions.count)",
                color: .blue
            )
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    @ViewBuilder
    private func statItem(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Intensity Selector
    
    @ViewBuilder
    private func intensitySelector() -> some View {
        HStack(spacing: 12) {
            ForEach(HeatmapIntensity.allCases, id: \.self) { intensity in
                Button {
                    selectedIntensity = intensity
                    generateHeatmap()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: intensity.icon)
                            .font(.title3)
                        Text(intensity.rawValue)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedIntensity == intensity ? Color.purple : Color.secondary.opacity(0.2))
                    .foregroundColor(selectedIntensity == intensity ? .white : .primary)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    // MARK: - Loading Overlay
    
    @ViewBuilder
    private func loadingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.purple)
                
                Text("Generating Heatmap...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
    
    // MARK: - Setup & Generation
    
    private func setupInitialView() {
        generateHeatmap()
        updateMapRegion()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoading = false
        }
    }
    
    private func generateHeatmap() {
        let allDwells = getAllDwells()
        guard !allDwells.isEmpty else {
            heatmapData = []
            return
        }
        
        // Group dwells by proximity to create clusters
        let clusters = clusterDwells(allDwells)
        
        // Generate heatmap points based on clusters
        var points: [HeatmapPoint] = []
        
        for cluster in clusters {
            let intensity = Double(cluster.dwells.count)
            let maxIntensity = Double(clusters.map { $0.dwells.count }.max() ?? 1)
            let normalizedIntensity = intensity / maxIntensity
            
            // Create multiple overlapping circles for smooth gradient
            let radiusSteps = selectedIntensity.radiusSteps
            for i in 0..<radiusSteps {
                let factor = Double(i + 1) / Double(radiusSteps)
                let radius = selectedIntensity.baseRadius * factor
                let opacity = normalizedIntensity * (1.0 - factor * 0.7) * selectedIntensity.opacityMultiplier
                
                let point = HeatmapPoint(
                    coordinate: cluster.center,
                    radius: radius,
                    intensity: normalizedIntensity,
                    opacity: opacity,
                    color: getHeatColor(for: normalizedIntensity)
                )
                points.append(point)
            }
        }
        
        heatmapData = points
    }
    
    private func clusterDwells(_ dwells: [DwellPoint]) -> [DwellCluster] {
        var clusters: [DwellCluster] = []
        var processedDwells: Set<UUID> = []
        
        let clusterRadius = selectedIntensity.clusterRadius
        
        for dwell in dwells {
            guard !processedDwells.contains(dwell.id) else { continue }
            
            // Find all dwells within cluster radius
            var clusterDwells: [DwellPoint] = [dwell]
            processedDwells.insert(dwell.id)
            
            for otherDwell in dwells {
                guard !processedDwells.contains(otherDwell.id) else { continue }
                
                let distance = CLLocation(latitude: dwell.location.latitude, longitude: dwell.location.longitude)
                    .distance(from: CLLocation(latitude: otherDwell.location.latitude, longitude: otherDwell.location.longitude))
                
                if distance <= clusterRadius {
                    clusterDwells.append(otherDwell)
                    processedDwells.insert(otherDwell.id)
                }
            }
            
            // Calculate cluster center (weighted by dwell duration)
            let totalDuration = clusterDwells.reduce(0.0) { $0 + $1.duration }
            let weightedLat = clusterDwells.reduce(0.0) { $0 + ($1.location.latitude * $1.duration) } / totalDuration
            let weightedLon = clusterDwells.reduce(0.0) { $0 + ($1.location.longitude * $1.duration) } / totalDuration
            
            let center = CLLocationCoordinate2D(latitude: weightedLat, longitude: weightedLon)
            clusters.append(DwellCluster(center: center, dwells: clusterDwells))
        }
        
        return clusters
    }
    
    private func getHeatColor(for intensity: Double) -> Color {
        // Color gradient: blue -> purple -> orange -> red
        switch intensity {
        case 0..<0.25:
            return .blue
        case 0.25..<0.5:
            return .purple
        case 0.5..<0.75:
            return .orange
        default:
            return .red
        }
    }
    
    private func getAllDwells() -> [DwellPoint] {
        storage.sessions.flatMap { $0.dwells }
    }
    
    private func getHotSpots() -> [DwellCluster] {
        let clusters = clusterDwells(getAllDwells())
        // Hot spots are clusters with 3+ visits
        return clusters.filter { $0.dwells.count >= 3 }
    }
    
    private func updateMapRegion() {
        let allDwells = getAllDwells()
        guard !allDwells.isEmpty else { return }
        
        let coordinates = allDwells.map { $0.location }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.02)
        )
        
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Models

struct HeatmapPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let radius: Double
    let intensity: Double
    let opacity: Double
    let color: Color
}

struct DwellCluster {
    let center: CLLocationCoordinate2D
    let dwells: [DwellPoint]
}

enum HeatmapIntensity: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var icon: String {
        switch self {
        case .low: return "circle"
        case .medium: return "circle.fill"
        case .high: return "circle.circle.fill"
        }
    }
    
    var baseRadius: Double {
        switch self {
        case .low: return 100
        case .medium: return 200
        case .high: return 300
        }
    }
    
    var radiusSteps: Int {
        switch self {
        case .low: return 3
        case .medium: return 5
        case .high: return 7
        }
    }
    
    var opacityMultiplier: Double {
        switch self {
        case .low: return 0.3
        case .medium: return 0.5
        case .high: return 0.7
        }
    }
    
    var clusterRadius: Double {
        switch self {
        case .low: return 50
        case .medium: return 75
        case .high: return 100
        }
    }
}

// MARK: - Settings View

struct HeatmapSettingsView: View {
    @Binding var selectedIntensity: HeatmapIntensity
    let onApply: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(HeatmapIntensity.allCases, id: \.self) { intensity in
                        Button {
                            selectedIntensity = intensity
                        } label: {
                            HStack {
                                Image(systemName: intensity.icon)
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(intensity.rawValue)
                                        .font(.headline)
                                    Text(getDescription(for: intensity))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedIntensity == intensity {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                } header: {
                    Text("Intensity Level")
                } footer: {
                    Text("Adjust how the heatmap displays your frequent locations. Higher intensity shows more concentrated areas.")
                }
                
                Section {
                    Button {
                        onApply()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Apply Changes")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Heatmap Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getDescription(for intensity: HeatmapIntensity) -> String {
        switch intensity {
        case .low:
            return "Subtle, wider spread"
        case .medium:
            return "Balanced visibility"
        case .high:
            return "Bold, concentrated areas"
        }
    }
}

#Preview {
    HeatmapView()
}