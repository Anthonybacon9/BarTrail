//
//  RouteVisualizerView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import SwiftUI
import MapKit

// Enhanced map view that colors route by speed
struct RouteVisualizerView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedSegment: RouteSegment?
    
    var body: some View {
        NavigationView {
            ZStack {
                Map(position: $cameraPosition) {
                    // Draw colored segments based on speed
                    ForEach(routeSegments, id: \.id) { segment in
                        MapPolyline(coordinates: segment.coordinates)
                            .stroke(segment.color, lineWidth: 4)
                    }
                    
                    // Start Point
                    if let firstLocation = session.route.first {
                        Annotation("Start", coordinate: firstLocation.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "flag.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    
                    // End Point
                    if let lastLocation = session.route.last, !session.isActive {
                        Annotation("End", coordinate: lastLocation.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 24, height: 24)
                                Image(systemName: "flag.checkered")
                                    .foregroundColor(.white)
                                    .font(.system(size: 12))
                            }
                        }
                    }
                    
                    // Dwell Points
                    ForEach(session.dwells) { dwell in
                        Annotation("", coordinate: dwell.location) {
                            ZStack {
                                Circle()
                                    .fill(.purple)
                                    .frame(width: 32, height: 32)
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18))
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .onAppear {
                    updateMapRegion()
                }
                
                // Legend
                VStack {
                    HStack {
                        Spacer()
                        legendView()
                            .padding()
                    }
                    Spacer()
                }
            }
            .navigationTitle("Route Visualization")
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
    
    // MARK: - Legend
    
    @ViewBuilder
    private func legendView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed")
                .font(.caption.bold())
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                Text("Fast")
                    .font(.caption2)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.orange)
                    .frame(width: 12, height: 12)
                Text("Medium")
                    .font(.caption2)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 12, height: 12)
                Text("Slow")
                    .font(.caption2)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.blue)
                    .frame(width: 12, height: 12)
                Text("Stationary")
                    .font(.caption2)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Route Segments
    
    private var routeSegments: [RouteSegment] {
        guard session.route.count > 1 else { return [] }
        
        var segments: [RouteSegment] = []
        
        for i in 0..<(session.route.count - 1) {
            let start = session.route[i]
            let end = session.route[i + 1]
            
            let coordinates = [start.coordinate, end.coordinate]
            let color = colorForSpeed(start.speed)
            
            segments.append(RouteSegment(
                id: UUID(),
                coordinates: coordinates,
                speed: start.speed,
                color: color
            ))
        }
        
        return segments
    }
    
    private func colorForSpeed(_ speed: CLLocationSpeed) -> Color {
        // Speed in m/s
        // < 0.5 m/s = stationary (blue)
        // 0.5 - 1.4 m/s = slow walking (green)
        // 1.4 - 2.5 m/s = normal walking (orange)
        // > 2.5 m/s = fast/running (red)
        
        if speed < 0 {
            return .gray // Invalid speed
        } else if speed < 0.5 {
            return .blue // Stationary
        } else if speed < 1.4 {
            return .green // Slow walk
        } else if speed < 2.5 {
            return .orange // Normal walk
        } else {
            return .red // Fast/running
        }
    }
    
    // MARK: - Map Region
    
    private func updateMapRegion() {
        guard !session.route.isEmpty else { return }
        
        let coordinates = session.route.map { $0.coordinate }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
        )
        
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Route Segment Model

struct RouteSegment: Identifiable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    let speed: CLLocationSpeed
    let color: Color
}

#Preview {
    let session = NightSession()
    session.endTime = Date()
    
    // Add mock locations with varying speeds
    let baseCoordinate = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    for i in 0..<30 {
        let offset = Double(i) * 0.0005
        let speed = Double.random(in: 0...3.0) // Varying speeds
        
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: baseCoordinate.latitude + offset,
                longitude: baseCoordinate.longitude + offset
            ),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: 0,
            speed: speed,
            timestamp: Date().addingTimeInterval(Double(i * 60))
        )
        session.addLocation(location)
    }
    
    return RouteVisualizerView(session: session)
}