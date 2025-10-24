import SwiftUI
import MapKit

struct MapSummaryView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDwell: DwellPoint?
    @State private var showingShareSheet = false
    @State private var dwellPlaceNames: [UUID: String] = [:]
    
    // Add these for screenshot functionality
    @State private var showingScreenshotSheet = false
    @State private var screenshotImage: UIImage?
    @State private var isCapturingScreenshot = false
    
    var body: some View {
            NavigationView {
                ZStack {
                    // Map View with screenshot capture
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            // Route Polyline
                            if session.route.count > 1 {
                                MapPolyline(coordinates: session.route.map { $0.coordinate })
                                    .stroke(.blue, lineWidth: 3)
                            }
                            
                            // Start Point
                            if let firstLocation = session.route.first {
                                Annotation("Start", coordinate: firstLocation.coordinate) {
                                    ZStack {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 20, height: 20)
                                        Image(systemName: "flag.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 10))
                                    }
                                }
                            }
                            
                            // End Point
                            if let lastLocation = session.route.last, !session.isActive {
                                Annotation("End", coordinate: lastLocation.coordinate) {
                                    ZStack {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 20, height: 20)
                                        Image(systemName: "flag.checkered")
                                            .foregroundColor(.white)
                                            .font(.system(size: 10))
                                    }
                                }
                            }
                            
                            // Dwell Points
                            ForEach(session.dwells) { dwell in
                                Annotation("", coordinate: dwell.location) {
                                    Button {
                                        selectedDwell = dwell
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(.purple)
                                                .frame(width: 30, height: 30)
                                            Image(systemName: "mappin.circle.fill")
                                                .foregroundColor(.white)
                                                .font(.system(size: 16))
                                        }
                                    }
                                }
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .onAppear {
                            updateMapRegion()
                            loadPlaceNames()
                        }
                    }
                    
                    // Summary Card at Bottom
                    VStack {
                        Spacer()
                        summaryCard()
                            .padding()
                    }
                    
                    // Dwell Detail Sheet
                    if let dwell = selectedDwell {
                        dwellDetailOverlay(dwell: dwell)
                    }
                    
                    // Screenshot capture overlay (hidden during capture)
                    if isCapturingScreenshot {
                        Color.clear
                            .background(.clear)
                    }
                }
                .navigationTitle("Night Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            captureScreenshot()
                        } label: {
                            Image(systemName: "camera.fill")
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            updateMapRegion()
                        } label: {
                            Image(systemName: "location.fill")
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                showingShareSheet = true
                            } label: {
                                Label("Share Options", systemImage: "square.and.arrow.up")
                            }
                            
                            if session.route.count > 1 {
                                NavigationLink {
                                    RouteVisualizerView(session: session)
                                } label: {
                                    Label("Speed View", systemImage: "speedometer")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .sheet(isPresented: $showingShareSheet) {
                    SessionShareView(session: session)
                        .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showingScreenshotSheet) {
                    if let screenshotImage = screenshotImage {
                        ScreenshotShareView(
                            image: screenshotImage,
                            session: session,
                            onDismiss: {
                                self.screenshotImage = nil
                                self.showingScreenshotSheet = false
                            }
                        )
                        .presentationDetents([.medium, .large])
                    }
                }
            }
        }
    
    // MARK: - Summary Card
    
    @ViewBuilder
    private func summaryCard() -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Night Summary")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 20) {
                statItem(icon: "clock.fill", label: "Duration", value: formatDuration(session.duration ?? 0))
                statItem(icon: "figure.walk", label: "Distance", value: formatDistance(session.totalDistance))
                statItem(icon: "mappin.circle.fill", label: "Stops", value: "\(session.dwells.count)")
            }
            
            if !session.dwells.isEmpty {
                Divider()
                
                HStack {
                    Text("Total Dwell Time:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(totalDwellTime()))
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    @ViewBuilder
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Screenshot Capture
    private func captureScreenshot() {
        isCapturingScreenshot = true
        
        // Give the UI time to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Get the main window
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                isCapturingScreenshot = false
                return
            }
            
            // Capture the entire screen without cropping
            let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
            let image = renderer.image { context in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            
            self.screenshotImage = image
            self.isCapturingScreenshot = false
            self.showingScreenshotSheet = true
        }
    }
        
        private func cropImageToContent(_ image: UIImage, in window: UIWindow) -> UIImage {
            let statusBarHeight = window.windowScene?.statusBarManager?.statusBarFrame.height ?? 0
            let navigationBarHeight: CGFloat = 44.0 // Approximate navigation bar height
            let bottomSafeArea = window.safeAreaInsets.bottom
            
            let cropRect = CGRect(
                x: 0,
                y: statusBarHeight + navigationBarHeight,
                width: image.size.width,
                height: image.size.height - (statusBarHeight + navigationBarHeight + bottomSafeArea + 100) // Extra padding for tab bar
            )
            
            guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
                return image
            }
            
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
    
    // MARK: - Dwell Detail Overlay
    
    @ViewBuilder
    private func dwellDetailOverlay(dwell: DwellPoint) -> some View {
        VStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let placeName = dwellPlaceNames[dwell.id] {
                            Text(placeName)
                                .font(.headline)
                        } else {
                            Text("Stop Details")
                                .font(.headline)
                        }
                        Text("Stop Details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        selectedDwell = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
                
                Divider()
                
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                    Text("Duration:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDuration(dwell.duration))
                        .bold()
                }
                
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("Arrived:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(dwell.startTime, style: .time)
                }
                
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                    Text("Departed:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(dwell.endTime, style: .time)
                }
                
                if let placeName = dwellPlaceNames[dwell.id] {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.blue)
                        Text("Location:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(placeName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        Text("Coordinates:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatCoordinate(dwell.location))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    selectedDwell = nil
                }
        )
    }
    
    // MARK: - Helper Methods
    
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
    
    private func totalDwellTime() -> TimeInterval {
        session.dwells.reduce(0) { $0 + $1.duration }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
    
    // MARK: - Load Place Names
    
    private func loadPlaceNames() {
        Task {
            for dwell in session.dwells {
                if let placeName = await GeocodingService.shared.getBestVenueName(for: dwell.location) {
                    await MainActor.run {
                        dwellPlaceNames[dwell.id] = placeName
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let session = NightSession()
    session.endTime = Date()
    
    // Add some mock locations for preview
    let baseCoordinate = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    for i in 0..<20 {
        let offset = Double(i) * 0.001
        let location = CLLocation(
            latitude: baseCoordinate.latitude + offset,
            longitude: baseCoordinate.longitude + offset
        )
        session.addLocation(location)
    }
    
    // Add mock dwells
    session.addDwell(DwellPoint(
        location: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
        startTime: Date().addingTimeInterval(-3600),
        endTime: Date().addingTimeInterval(-2400)
    ))
    
    session.addDwell(DwellPoint(
        location: CLLocationCoordinate2D(latitude: 51.5084, longitude: -0.1288),
        startTime: Date().addingTimeInterval(-2400),
        endTime: Date().addingTimeInterval(-1200)
    ))
    
    return MapSummaryView(session: session)
}
