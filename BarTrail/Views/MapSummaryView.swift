import SwiftUI
import MapKit
import PhotosUI
import Combine

struct MapSummaryView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = MapViewModel()
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDwell: DwellPoint?
    @State private var showingShareSheet = false
    @State private var dwellPlaceNames: [UUID: String] = [:]
    
    // Add these for screenshot functionality
    @State private var showingScreenshotSheet = false
    @State private var screenshotImage: UIImage?
    @State private var isCapturingScreenshot = false
    
    // Add this for photo overlay functionality
    @State private var showingPhotoOverlay = false
    
    @State private var showingTransparentOverlay = false
    @State private var transparentOverlayImage: UIImage?
    
    // ADD THESE FOR LOADING STATE
    @State private var isLoadingPlaceNames = true
    @State private var loadedCount = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                // Map View with screenshot capture
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // Route Polyline with gradient effect (draw multiple segments)
                        if session.route.count > 1 {
                            ForEach(Array(routeSegments.enumerated()), id: \.offset) { index, segment in
                                MapPolyline(coordinates: segment)
                                    .stroke(gradientColor(for: index, total: routeSegments.count), lineWidth: 3)
                            }
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
                                VStack(spacing: 4) {
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
                                    
                                    // Place name below marker - force refresh on change
                                    if let placeName = dwellPlaceNames[dwell.id] {
                                        Text(placeName)
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(.black.opacity(0.75))
                                            )
                                            .id(placeName) // Force re-render when name changes
                                    }
                                }
                            }
                        }
                    }
                    .mapStyle(.imagery(elevation: .realistic))
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
                
                // ADD LOADING OVERLAY
                if isLoadingPlaceNames && !session.dwells.isEmpty {
                    loadingOverlay()
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
                        
                        Button {
                            showingPhotoOverlay = true
                        } label: {
                            Label("Photo Overlay", systemImage: "photo.on.rectangle")
                        }
                        
                        Button {
                            generateTransparentOverlay()
                        } label: {
                            Label("Download Route Overlay", systemImage: "arrow.down.circle")
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
            .fullScreenCover(isPresented: $showingPhotoOverlay) {
                PhotoRouteOverlayView(session: session)
            }
            .sheet(isPresented: $showingTransparentOverlay) {
                if let overlayImage = transparentOverlayImage {
                    TransparentOverlayShareView(image: overlayImage)
                        .presentationDetents([.medium])
                }
            }
        }
    }
    
    // MARK: - Loading Overlay
    
    @ViewBuilder
    private func loadingOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Animated pulsing circle
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(isLoadingPlaceNames ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoadingPlaceNames)
                    
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.purple)
                }
                
                VStack(spacing: 8) {
                    Text("Loading Locations")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if session.dwells.count > 0 {
                        Text("\(loadedCount) of \(session.dwells.count)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        ProgressView(value: Double(loadedCount), total: Double(session.dwells.count))
                            .progressViewStyle(.linear)
                            .tint(.purple)
                            .frame(width: 200)
                    }
                }
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 20)
        }
    }
    
    private var routeSegments: [[CLLocationCoordinate2D]] {
        guard session.route.count > 1 else { return [] }
        
        var segments: [[CLLocationCoordinate2D]] = []
        for i in 0..<(session.route.count - 1) {
            segments.append([
                session.route[i].coordinate,
                session.route[i + 1].coordinate
            ])
        }
        return segments
    }

    private func gradientColor(for index: Int, total: Int) -> Color {
        let progress = Double(index) / Double(max(total - 1, 1))
        
        // Interpolate between blue and purple
        return Color(
            red: (1 - progress) * 0.0 + progress * 0.5,
            green: (1 - progress) * 0.5 + progress * 0.0,
            blue: (1 - progress) * 1.0 + progress * 0.5
        )
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
    
    private func generateTransparentOverlay() {
        Task {
            let overlay = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let image = RouteOverlayGenerator.shared.generateTransparentRoute(
                        from: session,
                        placeNames: dwellPlaceNames
                    )
                    continuation.resume(returning: image)
                }
            }
            
            if let overlay = overlay {
                transparentOverlayImage = overlay
                showingTransparentOverlay = true
            }
        }
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
    
    // MARK: - Load Place Names (UPDATED)
    
    private func loadPlaceNames() {
        // If no dwells, don't show loading
        guard !session.dwells.isEmpty else {
            isLoadingPlaceNames = false
            return
        }
        
        Task {
            await withTaskGroup(of: (UUID, String?).self) { group in
                for dwell in session.dwells {
                    group.addTask {
                        let placeName = await GeocodingService.shared.getBestVenueName(for: dwell.location)
                        return (dwell.id, placeName)
                    }
                }
                
                for await (dwellId, placeName) in group {
                    await MainActor.run {
                        loadedCount += 1
                        
                        if let placeName = placeName {
                            print("📍 Loaded place name: \(placeName) for dwell \(dwellId)")
                            dwellPlaceNames[dwellId] = placeName
                        }
                        
                        // Hide loading when all are done
                        if loadedCount >= session.dwells.count {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isLoadingPlaceNames = false
                            }
                        }
                    }
                }
            }
        }
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
}

// MARK: - Preview
#Preview {
    let session = NightSession()
    session.endTime = Date()
    
    // Liverpool nightlife route (Albert Schloss → Einsteins → Salt Dog Slim's)
    let dwellPoints = [
        DwellPoint(
            location: CLLocationCoordinate2D(latitude: 53.40420426605551, longitude: -2.9807664346635425), // Albert Schloss
            startTime: Date().addingTimeInterval(-7200),
            endTime: Date().addingTimeInterval(-5400)
        ),
        DwellPoint(
            location: CLLocationCoordinate2D(latitude: 53.403163839751876, longitude: -2.9804520646943606), // Einsteins
            startTime: Date().addingTimeInterval(-5400),
            endTime: Date().addingTimeInterval(-3600)
        ),
        DwellPoint(
            location: CLLocationCoordinate2D(latitude: 53.40116950967967, longitude: -2.9765373655910023), // Salt Dog Slim's
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date()
        )
    ]
    
    // Add them as dwell points and as route locations
    for dwell in dwellPoints {
        session.addDwell(dwell)
        session.addLocation(CLLocation(latitude: dwell.location.latitude, longitude: dwell.location.longitude))
    }
    
    return MapSummaryView(session: session)
}

class MapViewModel: ObservableObject {
    @Published var refreshTrigger = false
    
    func refresh() {
        refreshTrigger.toggle()
    }
}
