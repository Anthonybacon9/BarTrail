import SwiftUI
import MapKit
import PhotosUI
import Combine

struct MapSummaryView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = MapViewModel()
    
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedDwell: DwellPoint?
    @State private var showingShareSheet = false
    @State private var dwellPlaceNames: [UUID: String] = [:]
    
    @State private var showUpgrade = false
    @State private var showingDeleteAlert = false
    
    // Add these for screenshot functionality
    @State private var showingScreenshotSheet = false
    @State private var screenshotImage: UIImage?
    @State private var isCapturingScreenshot = false
    
    // Add this for photo overlay functionality
    @State private var showingPhotoOverlay = false
    
    @State private var isGeneratingOverlay = false
    @State private var showingTransparentOverlay = false
    @State private var transparentOverlayImage: UIImage?
    
    // Loading state - simplified
    @State private var isLoadingPlaceNames = true
    @State private var loadedCount = 0
    
    @StateObject private var mapStyleManager = MapStyleManager.shared
    
    // NEW: For venue editing
    @State private var showingVenueSelector = false
    @State private var editingDwell: DwellPoint?
    
    // NEW: For recenter functionality
    @State private var hasUserPanned = false
    
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
                                                .fill(dwell.isManuallySet ? .blue : .purple)
                                                .frame(width: 30, height: 30)
                                            
                                            // Show pencil icon if manually set
                                            if dwell.isManuallySet {
                                                Image(systemName: "pencil.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                            } else {
                                                Image(systemName: "mappin.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                            }
                                        }
                                    }
                                    
                                    // Place name below marker
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
                                    } else if isLoadingPlaceNames {
                                        // Show subtle loading indicator
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.white)
                                            .padding(6)
                                            .background(
                                                Capsule()
                                                    .fill(.black.opacity(0.75))
                                            )
                                    }
                                }
                            }
                        }
                    }
                    .mapStyle(mapStyleManager.getMapStyle())
                    .onMapCameraChange { context in
                        // Detect if user has manually moved the map
                        hasUserPanned = true
                    }
                    .onAppear {
                        updateMapRegion()
                        loadPlaceNames()
                    }
                }
                
//                // Recenter button - only show when user has panned
//                if hasUserPanned && !session.route.isEmpty {
//                    VStack {
//                        HStack {
//                            Spacer()
//                            Button {
//                                withAnimation(.easeInOut(duration: 0.5)) {
//                                    updateMapRegion()
//                                    hasUserPanned = false
//                                }
//                            } label: {
//                                HStack(spacing: 6) {
//                                    Image(systemName: "location.fill")
//                                        .font(.system(size: 14))
//                                    Text("Recenter")
//                                        .font(.subheadline.bold())
//                                }
//                                .foregroundColor(.white)
//                                .padding(.horizontal, 16)
//                                .padding(.vertical, 10)
//                                .background(.blue)
//                                .cornerRadius(20)
//                                .shadow(radius: 5)
//                            }
//                            .padding(.trailing, 16)
//                            .padding(.top, 8)
//                        }
//                        Spacer()
//                    }
//                    .transition(.move(edge: .top).combined(with: .opacity))
//                }
                
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
                
                // Simplified loading toast - appears briefly at top
                if isLoadingPlaceNames && !session.dwells.isEmpty && loadedCount < session.dwells.count {
                    VStack {
                        HStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(.white)
                            
                            Text("Loading locations...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(loadedCount)/\(session.dwells.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("\(Text(session.startTime, style: .date))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.5)) {
                                            updateMapRegion()
                                        }
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
                            if revenueCatManager.isSubscribed {
                                generateTransparentOverlay()
                            } else {
                                showUpgrade = true
                            }
                        } label: {
                            if isGeneratingOverlay {
                                Label("Generating Overlay...", systemImage: "arrow.down.circle")
                            } else {
                                Label("Download Route Overlay", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isGeneratingOverlay)
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .foregroundColor(.red)
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
            .fullScreenCover(isPresented: $showUpgrade) {
                PremiumUpgradeSheet()
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
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Generating overlay...")
                            .foregroundColor(.secondary)
                    }
                    .presentationDetents([.medium])
                }
            }
            // NEW: Venue selector sheet
            .sheet(isPresented: $showingVenueSelector) {
                if let editingDwell = editingDwell {
                    VenueSelectorSheet(
                        dwell: editingDwell,
                        selectedVenueName: Binding(
                            get: { editingDwell.manualPlaceName },
                            set: { newName in
                                updateDwellVenueName(dwellId: editingDwell.id, newName: newName)
                            }
                        )
                    )
                }
            }
            .alert("Delete Session", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    SessionStorage.shared.deleteSession(session)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this session? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Update Dwell Venue Name
    
    private func updateDwellVenueName(dwellId: UUID, newName: String?) {
        // Find the dwell in the session
        guard let index = session.dwells.firstIndex(where: { $0.id == dwellId }) else {
            return
        }
        
        // Update the manual place name
        session.dwells[index].manualPlaceName = newName
        
        // Update the display name in our local state
        if let newName = newName {
            // User selected a new name
            dwellPlaceNames[dwellId] = newName
        } else {
            // User reset - go back to original auto-detected name
            if let originalName = session.dwells[index].placeName {
                dwellPlaceNames[dwellId] = originalName
            } else {
                // If no original name exists, fetch it
                Task {
                    if let fetchedName = await GeocodingService.shared.getBestVenueName(for: session.dwells[index].location) {
                        await MainActor.run {
                            dwellPlaceNames[dwellId] = fetchedName
                            // Also save it to the dwell
                            if let idx = session.dwells.firstIndex(where: { $0.id == dwellId }) {
                                session.dwells[idx].placeName = fetchedName
                            }
                        }
                    }
                }
            }
        }
        
        // Save the session
        SessionStorage.shared.saveSession(session)
        
        // Force UI update
        viewModel.refresh()
        
        print("✅ Updated venue name for dwell \(dwellId): \(newName ?? "reset to original")")
    }
    
    private func deleteSession() {
        let alert = UIAlertController(
            title: "Delete Session",
            message: "Are you sure you want to delete this session? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            SessionStorage.shared.deleteSession(session)
            dismiss()
        })
        
        // Present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
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
            if session.drinks.total > 0 {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Drinks Consumed:")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(session.drinks.total) total")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                    }
                    
                    // Drink breakdown
                    VStack(spacing: 4) {
                        if session.drinks.beer > 0 {
                            drinkRow(icon: "🍺", name: "Beer", count: session.drinks.beer)
                        }
                        if session.drinks.spirits > 0 {
                            drinkRow(icon: "🥃", name: "Spirits", count: session.drinks.spirits)
                        }
                        if session.drinks.cocktails > 0 {
                            drinkRow(icon: "🍹", name: "Cocktails", count: session.drinks.cocktails)
                        }
                        if session.drinks.shots > 0 {
                            drinkRow(icon: "🥃", name: "Shots", count: session.drinks.shots)
                        }
                        if session.drinks.wine > 0 {
                            drinkRow(icon: "🍷", name: "Wine", count: session.drinks.wine)
                        }
                        if session.drinks.other > 0 {
                            drinkRow(icon: "🍻", name: "Other", count: session.drinks.other)
                        }
                    }
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                isCapturingScreenshot = false
                return
            }
            
            let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
            let image = renderer.image { context in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            
            self.screenshotImage = image
            self.isCapturingScreenshot = false
            self.showingScreenshotSheet = true
        }
    }
    
    @ViewBuilder
    private func drinkRow(icon: String, name: String, count: Int) -> some View {
        HStack {
            Text(icon)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption.bold())
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
        guard !isGeneratingOverlay else { return }
        
        isGeneratingOverlay = true
        
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
            
            await MainActor.run {
                isGeneratingOverlay = false
                transparentOverlayImage = overlay
                if overlay != nil {
                    showingTransparentOverlay = true
                }
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
    
    // MARK: - Load Place Names (IMPROVED)
    
    private func loadPlaceNames() {
        guard !session.dwells.isEmpty else {
            isLoadingPlaceNames = false
            return
        }
        
        Task {
            await withTaskGroup(of: (UUID, String?).self) { group in
                for dwell in session.dwells {
                    group.addTask {
                        // Use displayName if available (respects manual override)
                        if let displayName = await dwell.displayName {
                            return (dwell.id, displayName)
                        }
                        
                        // Otherwise fetch from geocoding service
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
                        
                        // Auto-hide loading indicator after all loaded
                        if loadedCount >= session.dwells.count {
                            // Brief delay before hiding
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isLoadingPlaceNames = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Dwell Detail Overlay (UPDATED with Edit Button)
    
    @ViewBuilder
    private func dwellDetailOverlay(dwell: DwellPoint) -> some View {
        VStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let placeName = dwellPlaceNames[dwell.id] {
                            HStack {
                                Text(placeName)
                                    .font(.headline)
                                
                                // Show indicator if manually set
                                if dwell.isManuallySet {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                            }
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
                
                Divider()
                
                // NEW: Edit Venue Button
                Button {
                    editingDwell = dwell
                    selectedDwell = nil
                    showingVenueSelector = true
                } label: {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                        Text(dwell.isManuallySet ? "Change Venue" : "Correct Venue")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(dwell.isManuallySet ? Color.blue : Color.purple)
                    .cornerRadius(12)
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
