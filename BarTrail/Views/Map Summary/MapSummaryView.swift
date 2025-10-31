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
                                            // Different colors based on type
                                            Circle()
                                                .fill(markerColor(for: dwell))
                                                .frame(width: 30, height: 30)
                                            
                                            // Show different icons
                                            if dwell.isManuallySet {
                                                Image(systemName: "pencil.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                            } else if dwell.isRevisit {
                                                Image(systemName: "arrow.uturn.left.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                            } else {
                                                Image(systemName: "mappin.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.system(size: 16))
                                            }
                                            
                                            // 🆕 Badge for confidence level
                                            if dwell.confidence == .low || dwell.confidence == .estimated {
                                                VStack {
                                                    HStack {
                                                        Spacer()
                                                        Circle()
                                                            .fill(.orange)
                                                            .frame(width: 8, height: 8)
                                                    }
                                                    Spacer()
                                                }
                                                .frame(width: 30, height: 30)
                                            }
                                        }
                                    }
                                    
                                    // Place name with type indicator
                                    if let placeName = dwellPlaceNames[dwell.id] {
                                        HStack(spacing: 4) {
                                            Text(dwell.dwellType.icon)
                                                .font(.caption2)
                                            Text(placeName)
                                                .font(.caption.bold())
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(.black.opacity(0.75))
                                        )
                                        .id(placeName)
                                    } else if isLoadingPlaceNames {
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
                    if #available(iOS 26.0, *) {
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
                            .glassEffect(in: .rect)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                            .padding(.horizontal)
                            .padding(.top, 8)
                            
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
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
    
    private func markerColor(for dwell: DwellPoint) -> Color {
        if dwell.isManuallySet {
            return .blue
        } else if dwell.isRevisit {
            return .orange
        } else {
            // Color by dwell type
            switch dwell.dwellType {
            case .passthrough: return .gray
            case .quickStop: return .orange
            case .shortVisit: return .purple
            case .longStop: return .pink
            case .marathon: return .red
            }
        }
    }
    
    // MARK: - Summary Card
    
    // Replace your summaryCard() function in MapSummaryView with this:

    @ViewBuilder
    private func summaryCard() -> some View {
        if #available(iOS 26.0, *) {
            VStack(spacing: 0) {
                // Main Stats Row
                HStack(spacing: 16) {
                    compactStat(icon: "clock.fill", value: formatDuration(session.duration ?? 0))
                    Divider().frame(height: 30)
                    compactStat(icon: "figure.walk", value: formatDistance(session.totalDistance))
                    Divider().frame(height: 30)
                    compactStat(icon: "mappin.circle.fill", value: "\(session.dwells.count)")
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Expandable Details
                if !session.dwells.isEmpty || session.drinks.total > 0 || session.rating != nil {
                    Divider()
                    
                    VStack(spacing: 8) {
                        // Dwell Type Breakdown (compact, single line)
                        if !session.dwells.isEmpty {
                            dwellTypeRow()
                        }
                        
                        // Drinks (compact, single line)
                        if session.drinks.total > 0 {
                            drinksRow()
                        }
                        
                        // Rating
                        if let rating = session.rating {
                            ratingRow(rating: rating)
                        }
                        
                        // Revisits indicator
                        let revisitCount = session.dwells.filter { $0.isRevisit }.count
                        if revisitCount > 0 {
                            revisitRow(count: revisitCount)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .glassEffect(in: .rect)
            .cornerRadius(16)
            .shadow(radius: 10)
        } else {
            VStack(spacing: 0) {
                // Main Stats Row
                HStack(spacing: 16) {
                    compactStat(icon: "clock.fill", value: formatDuration(session.duration ?? 0))
                    Divider().frame(height: 30)
                    compactStat(icon: "figure.walk", value: formatDistance(session.totalDistance))
                    Divider().frame(height: 30)
                    compactStat(icon: "mappin.circle.fill", value: "\(session.dwells.count)")
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                
                // Expandable Details
                if !session.dwells.isEmpty || session.drinks.total > 0 || session.rating != nil {
                    Divider()
                    
                    VStack(spacing: 8) {
                        // Dwell Type Breakdown (compact, single line)
                        if !session.dwells.isEmpty {
                            dwellTypeRow()
                        }
                        
                        // Drinks (compact, single line)
                        if session.drinks.total > 0 {
                            drinksRow()
                        }
                        
                        // Rating
                        if let rating = session.rating {
                            ratingRow(rating: rating)
                        }
                        
                        // Revisits indicator
                        let revisitCount = session.dwells.filter { $0.isRevisit }.count
                        if revisitCount > 0 {
                            revisitRow(count: revisitCount)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 10)
        }
    }

    // MARK: - Compact Stat Item
    @ViewBuilder
    private func compactStat(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            Text(value)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dwell Type Row (Single Line)
    @ViewBuilder
    private func dwellTypeRow() -> some View {
        let grouped = session.dwells.groupedByType()
        
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.caption2)
                .foregroundColor(.purple)
                .frame(width: 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([DwellType.passthrough, .quickStop, .shortVisit, .longStop, .marathon], id: \.self) { type in
                        if let count = grouped[type]?.count, count > 0 {
                            HStack(spacing: 3) {
                                Text(type.icon)
                                    .font(.caption2)
                                Text("\(count)")
                                    .font(.caption2.bold())
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(typeColor(type).opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Drinks Row (Single Line)
    @ViewBuilder
    private func drinksRow() -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wineglass.fill")
                .font(.caption2)
                .foregroundColor(.orange)
                .frame(width: 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Total
                    HStack(spacing: 3) {
                        Text("Total:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(session.drinks.total)")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                    
                    // Individual types (only if > 0)
                    if session.drinks.beer > 0 {
                        drinkBadge(icon: "🍺", count: session.drinks.beer)
                    }
                    if session.drinks.spirits > 0 {
                        drinkBadge(icon: "🍾", count: session.drinks.spirits)
                    }
                    if session.drinks.cocktails > 0 {
                        drinkBadge(icon: "🍹", count: session.drinks.cocktails)
                    }
                    if session.drinks.shots > 0 {
                        drinkBadge(icon: "🥃", count: session.drinks.shots)
                    }
                    if session.drinks.wine > 0 {
                        drinkBadge(icon: "🍷", count: session.drinks.wine)
                    }
                    if session.drinks.other > 0 {
                        drinkBadge(icon: "🧃", count: session.drinks.other)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func drinkBadge(icon: String, count: Int) -> some View {
        HStack(spacing: 2) {
            Text(icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption2.bold())
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(6)
    }

    // MARK: - Rating Row
    @ViewBuilder
    private func ratingRow(rating: Int) -> some View {
        HStack(spacing: 6) {
            
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: index < rating ? "star.fill" : "star")
                        .font(.caption2)
                        .foregroundColor(index < rating ? .yellow : .gray)
                }
            }
            
            Spacer()
            
            Text("Night Rating")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Revisit Row
    @ViewBuilder
    private func revisitRow(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.uturn.left.circle.fill")
                .font(.caption2)
                .foregroundColor(.orange)
                .frame(width: 16)
            
            Text("Returned to \(count) venue\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }

    // MARK: - Helper Function
    private func typeColor(_ type: DwellType) -> Color {
        switch type {
        case .passthrough: return .gray
        case .quickStop: return .orange
        case .shortVisit: return .blue
        case .longStop: return .purple
        case .marathon: return .pink
        }
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
        if #available(iOS 26.0, *) {
            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 12) {
                    // Header with venue name
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let placeName = dwellPlaceNames[dwell.id] {
                                HStack(spacing: 6) {
                                    Text(placeName)
                                        .font(.headline)
                                    
                                    // Manual edit indicator
                                    if dwell.isManuallySet {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    
                                    // Revisit indicator
                                    if dwell.isRevisit {
                                        Image(systemName: "arrow.uturn.left.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                            } else {
                                Text("Stop Details")
                                    .font(.headline)
                            }
                            
                            // Dwell type and confidence in one line
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    Text(dwell.dwellType.icon)
                                        .font(.caption2)
                                    Text(dwell.dwellType.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor(dwell.dwellType).opacity(0.15))
                                .cornerRadius(6)
                                
                                HStack(spacing: 3) {
                                    Text(dwell.confidence.icon)
                                        .font(.caption2)
                                    Text(dwell.confidence.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(confidenceColor(dwell.confidence).opacity(0.15))
                                .cornerRadius(6)
                            }
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
                    
                    // Time details - compact 2 column layout
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(
                                icon: "clock.fill",
                                label: "Duration",
                                value: formatDuration(dwell.duration),
                                color: .blue
                            )
                            detailRow(
                                icon: "arrow.right.circle.fill",
                                label: "Arrived",
                                value: dwell.startTime.formatted(date: .omitted, time: .shortened),
                                color: .green
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(
                                icon: "calendar",
                                label: "Date",
                                value: dwell.startTime.formatted(date: .abbreviated, time: .omitted),
                                color: .purple
                            )
                            detailRow(
                                icon: "arrow.left.circle.fill",
                                label: "Departed",
                                value: dwell.endTime.formatted(date: .omitted, time: .shortened),
                                color: .red
                            )
                        }
                    }
                    
                    // Revisit info banner (if applicable)
                    if dwell.isRevisit {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.left.circle.fill")
                                .foregroundColor(.orange)
                            Text("You returned to this venue")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Edit venue button
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
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(dwell.isManuallySet ? Color.blue : Color.purple)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .glassEffect(in: .rect)
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
        } else {
            VStack {
                Spacer()
                
                VStack(alignment: .leading, spacing: 12) {
                    // Header with venue name
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let placeName = dwellPlaceNames[dwell.id] {
                                HStack(spacing: 6) {
                                    Text(placeName)
                                        .font(.headline)
                                    
                                    // Manual edit indicator
                                    if dwell.isManuallySet {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                    
                                    // Revisit indicator
                                    if dwell.isRevisit {
                                        Image(systemName: "arrow.uturn.left.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                            } else {
                                Text("Stop Details")
                                    .font(.headline)
                            }
                            
                            // Dwell type and confidence in one line
                            HStack(spacing: 8) {
                                HStack(spacing: 3) {
                                    Text(dwell.dwellType.icon)
                                        .font(.caption2)
                                    Text(dwell.dwellType.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor(dwell.dwellType).opacity(0.15))
                                .cornerRadius(6)
                                
                                HStack(spacing: 3) {
                                    Text(dwell.confidence.icon)
                                        .font(.caption2)
                                    Text(dwell.confidence.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(confidenceColor(dwell.confidence).opacity(0.15))
                                .cornerRadius(6)
                            }
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
                    
                    // Time details - compact 2 column layout
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(
                                icon: "clock.fill",
                                label: "Duration",
                                value: formatDuration(dwell.duration),
                                color: .blue
                            )
                            detailRow(
                                icon: "arrow.right.circle.fill",
                                label: "Arrived",
                                value: dwell.startTime.formatted(date: .omitted, time: .shortened),
                                color: .green
                            )
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            detailRow(
                                icon: "calendar",
                                label: "Date",
                                value: dwell.startTime.formatted(date: .abbreviated, time: .omitted),
                                color: .purple
                            )
                            detailRow(
                                icon: "arrow.left.circle.fill",
                                label: "Departed",
                                value: dwell.endTime.formatted(date: .omitted, time: .shortened),
                                color: .red
                            )
                        }
                    }
                    
                    // Revisit info banner (if applicable)
                    if dwell.isRevisit {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.left.circle.fill")
                                .foregroundColor(.orange)
                            Text("You returned to this venue")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // Edit venue button
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
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
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

    // MARK: - Detail Row Helper
    @ViewBuilder
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.bold())
            }
        }
    }
    // 🆕 Helper function for confidence colors
    private func confidenceColor(_ confidence: DwellConfidence) -> Color {
        switch confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        case .estimated: return .purple
        }
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
