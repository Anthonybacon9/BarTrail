import SwiftUI
import PhotosUI
import Photos

struct PhotoRouteOverlayView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var routeOverlay: UIImage?
    @State private var statsOverlay: UIImage?
    @State private var overlayOpacity: Double = 0.9
    @State private var overlayScale: CGFloat = 1.0
    @State private var overlayOffset: CGSize = .zero
    @State private var compositeImage: UIImage?
    @State private var showingShareSheet = false
    @State private var isGeneratingComposite = false
    @State private var showSaveSuccess = false
    @State private var dwellPlaceNames: [UUID: String] = [:]
    
    @State private var showWatermark: Bool = true
    @State private var watermarkText: String = "BarTrail"
    @State private var watermarkPosition: WatermarkPosition = .bottomRight
    @State private var watermarkOpacity: Double = 0.8
    
    @State private var selectedOverlayType: OverlayType = .route
    @State private var showingDateMismatchAlert = false
    
    enum OverlayType: String, CaseIterable {
        case route = "Route Map"
        case stats = "Stats Grid"
        
        var icon: String {
            switch self {
            case .route: return "map"
            case .stats: return "chart.bar.fill"
            }
        }
    }
    
    enum WatermarkPosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, center
        
        var displayName: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            case .center: return "Center"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                if let baseImage = selectedImage {
                    // Canvas view that maintains aspect ratios (BEHIND)
                    CanvasEditorView(
                        baseImage: baseImage,
                        overlayImage: currentOverlay,
                        overlayOpacity: $overlayOpacity,
                        overlayScale: $overlayScale,
                        overlayOffset: $overlayOffset
                    )
                    .ignoresSafeArea()
                    
                    // UI overlays (IN FRONT)
                    VStack(spacing: 0) {
                        // Overlay type picker at top
                        overlayTypePicker()
                            .padding(.top, 8)
                        
                        Spacer()
                        
                        // Controls at bottom
                        controlsPanel()
                            .padding()
                    }
                    
                    if isGeneratingComposite {
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Generating Image...")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                    }
                } else {
                    photoPickerView()
                }
            }
            .navigationTitle("Photo Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Clean up memory before dismissing
                        selectedImage = nil
                        routeOverlay = nil
                        statsOverlay = nil
                        compositeImage = nil
                        dismiss()
                    }
                }
                
                if selectedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            generateAndShareComposite()
                        }
                        .disabled(isGeneratingComposite)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let composite = compositeImage {
                    ShareSheet(activityItems: [composite])
                }
            }
            .alert("Saved to Photos", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your route overlay has been saved to your photo library.")
            }
            .alert("Photo Not From This Night", isPresented: $showingDateMismatchAlert) {
                Button("Choose Another", role: .cancel) {
                    selectedImage = nil
                }
                Button("Use Anyway", role: .destructive) {
                    // Allow them to proceed
                }
            } message: {
                Text("This photo wasn't taken during your night out. For best results, choose a photo from \(formatSessionDateRange()).")
            }
        }
        .task {
            await loadPlaceNames()
            generateRouteOverlay()
            generateStatsOverlay()
        }
        .onDisappear {
            // Critical: Clean up all large images when view disappears
            selectedImage = nil
            routeOverlay = nil
            statsOverlay = nil
            compositeImage = nil
        }
    }
    
    // MARK: - Current Overlay
    
    private var currentOverlay: UIImage? {
        switch selectedOverlayType {
        case .route:
            return routeOverlay
        case .stats:
            return statsOverlay
        }
    }
    
    // MARK: - Overlay Type Picker
    
    @ViewBuilder
    private func overlayTypePicker() -> some View {
        HStack(spacing: 12) {
            ForEach(OverlayType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedOverlayType = type
                        // Reset position when switching overlays
                        overlayScale = 1.0
                        overlayOffset = .zero
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: type.icon)
                            .font(.caption)
                        Text(type.rawValue)
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(selectedOverlayType == type ? .white : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedOverlayType == type
                            ? Color.blue
                            : Color.white.opacity(0.8)
                    )
                    .cornerRadius(20)
                    .shadow(radius: 3)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Generate Composite (MEMORY OPTIMIZED)
    
    private func generateAndShareComposite() {
        guard let baseImage = selectedImage,
              let overlay = currentOverlay else { return }
        
        isGeneratingComposite = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Use autoreleasepool to immediately free memory after generation
            let composite = autoreleasepool { () -> UIImage? in
                let baseSize = baseImage.size
                let overlaySize = overlay.size
                
                // Limit maximum output size to prevent memory issues
                let maxDimension: CGFloat = 4096 // 4K max
                var finalSize = baseSize
                
                if baseSize.width > maxDimension || baseSize.height > maxDimension {
                    let scale = min(maxDimension / baseSize.width, maxDimension / baseSize.height)
                    finalSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
                }
                
                let scaledOverlaySize = CGSize(
                    width: overlaySize.width * overlayScale,
                    height: overlaySize.height * overlayScale
                )
                
                let imageScale = finalSize.width / UIScreen.main.bounds.width
                let scaledOffset = CGSize(
                    width: overlayOffset.width * imageScale,
                    height: overlayOffset.height * imageScale
                )
                
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0 // Use 1.0 scale for exact pixel control
                format.opaque = true // More efficient if no transparency needed
                
                let renderer = UIGraphicsImageRenderer(size: finalSize, format: format)
                
                return renderer.image { context in
                    // Draw base image (scaled if needed)
                    if finalSize != baseSize {
                        baseImage.draw(in: CGRect(origin: .zero, size: finalSize), blendMode: .normal, alpha: 1.0)
                    } else {
                        baseImage.draw(in: CGRect(origin: .zero, size: finalSize))
                    }
                    
                    // Calculate overlay position
                    let overlayOrigin = CGPoint(
                        x: (finalSize.width - scaledOverlaySize.width) / 2 + scaledOffset.width,
                        y: (finalSize.height - scaledOverlaySize.height) / 2 + scaledOffset.height
                    )
                    
                    let overlayRect = CGRect(origin: overlayOrigin, size: scaledOverlaySize)
                    overlay.draw(in: overlayRect, blendMode: .normal, alpha: overlayOpacity)
                    
                    // Draw watermark
                    self.drawWatermark(in: context, size: finalSize)
                }
            }
            
            guard let finalComposite = composite else {
                DispatchQueue.main.async {
                    self.isGeneratingComposite = false
                }
                return
            }
            
            // Save to photos
            UIImageWriteToSavedPhotosAlbum(finalComposite, nil, nil, nil)
            
            DispatchQueue.main.async {
                self.compositeImage = finalComposite
                self.isGeneratingComposite = false
                self.showSaveSuccess = true
                self.showingShareSheet = true
            }
        }
    }
    
    // MARK: - Watermark Methods

    private func drawWatermark(in context: UIGraphicsImageRendererContext, size: CGSize) {
        guard showWatermark else { return }
        
        let ctx = context.cgContext
        let text = NSString(string: watermarkText)
        
        let fontSize: CGFloat = size.width * 0.025
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(watermarkOpacity),
            .strokeColor: UIColor.black.withAlphaComponent(watermarkOpacity * 0.7),
            .strokeWidth: -1.0
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let padding: CGFloat = size.width * 0.02
        
        let textRect: CGRect = {
            switch watermarkPosition {
            case .topLeft:
                return CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
            case .topRight:
                return CGRect(x: size.width - textSize.width - padding, y: padding, width: textSize.width, height: textSize.height)
            case .bottomLeft:
                return CGRect(x: padding, y: size.height - textSize.height - padding, width: textSize.width, height: textSize.height)
            case .bottomRight:
                return CGRect(x: size.width - textSize.width - padding, y: size.height - textSize.height - padding, width: textSize.width, height: textSize.height)
            case .center:
                return CGRect(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2, width: textSize.width, height: textSize.height)
            }
        }()
        
        ctx.setShadow(offset: CGSize(width: 1, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        text.draw(in: textRect, withAttributes: attributes)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }
    
    // MARK: - Controls Panel
    
    @ViewBuilder
    private func controlsPanel() -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "circle.lefthalf.filled") // Changed from 'opacity'
                    .foregroundColor(.white)
                Slider(value: $overlayOpacity, in: 0...1)
                    .tint(.white)
                Text("\(Int(overlayOpacity * 100))%")
                    .foregroundColor(.white)
                    .frame(width: 50)
            }
            
            HStack {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(.white)
                Slider(value: $overlayScale, in: 0.5...2.0)
                    .tint(.white)
                Text("\(Int(overlayScale * 100))%")
                    .foregroundColor(.white)
                    .frame(width: 50)
            }
            
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        overlayOpacity = 0.9
                        overlayScale = 1.0
                        overlayOffset = .zero
                    }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                }
                
                Button {
                    generateAndShareComposite()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .disabled(isGeneratingComposite)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
    
    // MARK: - Photo Picker View
    
    @ViewBuilder
    private func photoPickerView() -> some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Select a Photo")
                .font(.title2.bold())
            
            Text("Choose a photo from your night to overlay the route on")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                if #available(iOS 26.0, *) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .glassEffect(.regular.tint(.blue))
                        .cornerRadius(12)
                } else {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                loadPhoto(from: newValue)
            }
        }
        .padding()
    }
    
    // MARK: - Generate Route Overlay (MEMORY OPTIMIZED)
    
    private func generateRouteOverlay() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Generate at reasonable size (1080x1080 is plenty for overlay)
            let overlay = autoreleasepool {
                RouteOverlayGenerator.shared.generateRouteWithOutline(
                    from: session,
                    placeNames: dwellPlaceNames,
                    size: CGSize(width: 1080, height: 1080)
                )
            }
            
            DispatchQueue.main.async {
                self.routeOverlay = overlay
            }
        }
    }
    
    // MARK: - Generate Stats Overlay
    
    private func generateStatsOverlay() {
        DispatchQueue.global(qos: .userInitiated).async {
            let overlay = autoreleasepool {
                StatsOverlayGenerator.shared.generateStatsGrid(
                    from: session,
                    size: CGSize(width: 1080, height: 1080)
                )
            }
            
            DispatchQueue.main.async {
                self.statsOverlay = overlay
            }
        }
    }
    
    // MARK: - Load Photo (MEMORY OPTIMIZED + DATE VALIDATION)
    
    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            // Get the asset identifier and check date
            if let assetIdentifier = item.itemIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
                if let asset = fetchResult.firstObject,
                   let creationDate = asset.creationDate {
                    if !isPhotoFromSession(photoDate: creationDate) {
                        await MainActor.run {
                            showingDateMismatchAlert = true
                            selectedPhoto = nil
                        }
                        return
                    }
                }
            }
            
            // Load the actual image data
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Decompress image on background thread
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        autoreleasepool {
                            if let image = UIImage(data: data) {
                                // Downscale if image is huge (> 4K)
                                let maxDimension: CGFloat = 4096
                                if image.size.width > maxDimension || image.size.height > maxDimension {
                                    let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                                    let newSize = CGSize(
                                        width: image.size.width * scale,
                                        height: image.size.height * scale
                                    )
                                    
                                    let format = UIGraphicsImageRendererFormat()
                                    format.scale = 1.0
                                    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                                    let resized = renderer.image { _ in
                                        image.draw(in: CGRect(origin: .zero, size: newSize))
                                    }
                                    
                                    DispatchQueue.main.async {
                                        self.selectedImage = resized
                                        self.selectedPhoto = nil
                                        continuation.resume()
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        self.selectedImage = image
                                        self.selectedPhoto = nil
                                        continuation.resume()
                                    }
                                }
                            } else {
                                DispatchQueue.main.async {
                                    continuation.resume()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Photo Date Validation
    
    private func isPhotoFromSession(photoDate: Date) -> Bool {
        let sessionStart = session.startTime
        let sessionEnd = session.endTime ?? Date()
        
        // Allow 1 hour before and after for flexibility
        let bufferTime: TimeInterval = 3600
        let startWithBuffer = sessionStart.addingTimeInterval(-bufferTime)
        let endWithBuffer = sessionEnd.addingTimeInterval(bufferTime)
        
        return photoDate >= startWithBuffer && photoDate <= endWithBuffer
    }
    
    private func formatSessionDateRange() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        let start = formatter.string(from: session.startTime)
        if let end = session.endTime {
            let endStr = formatter.string(from: end)
            return "\(start) - \(endStr)"
        }
        return start
    }
    
    // MARK: - Load Place Names

    private func loadPlaceNames() {
        Task {
            for dwell in session.dwells {
                if let displayName = dwell.displayName {
                    await MainActor.run {
                        dwellPlaceNames[dwell.id] = displayName
                    }
                } else {
                    if let placeName = await GeocodingService.shared.getBestVenueName(for: dwell.location) {
                        await MainActor.run {
                            dwellPlaceNames[dwell.id] = placeName
                        }
                    }
                }
            }
            await MainActor.run {
                generateRouteOverlay()
            }
        }
    }
}

// MARK: - Canvas Editor View (MEMORY EFFICIENT)

struct CanvasEditorView: View {
    let baseImage: UIImage
    let overlayImage: UIImage?
    
    @Binding var overlayOpacity: Double
    @Binding var overlayScale: CGFloat
    @Binding var overlayOffset: CGSize
    
    @State private var dragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            canvasContent(containerSize: geometry.size)
        }
    }
    
    @ViewBuilder
    private func canvasContent(containerSize: CGSize) -> some View {
        let baseAspect = baseImage.size.width / baseImage.size.height
        let viewAspect = containerSize.width / containerSize.height
        
        let baseDisplaySize: CGSize = {
            if baseAspect > viewAspect {
                return CGSize(
                    width: containerSize.width,
                    height: containerSize.width / baseAspect
                )
            } else {
                return CGSize(
                    width: containerSize.height * baseAspect,
                    height: containerSize.height
                )
            }
        }()
        
        let displayScale = baseDisplaySize.width / baseImage.size.width
        
        ZStack {
            Image(uiImage: baseImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: baseDisplaySize.width, height: baseDisplaySize.height)
            
            if let overlay = overlayImage {
                let overlayDisplaySize = CGSize(
                    width: overlay.size.width * displayScale,
                    height: overlay.size.height * displayScale
                )
                
                Image(uiImage: overlay)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: overlayDisplaySize.width, height: overlayDisplaySize.height)
                    .scaleEffect(overlayScale)
                    .offset(overlayOffset)
                    .opacity(overlayOpacity)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                overlayOffset = value.translation
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                overlayScale = value
                            }
                    )
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }
}

#Preview {
    let session = NightSession()
    session.endTime = Date()
    
    for i in 0..<20 {
        let offset = Double(i) * 0.001
        let location = CLLocation(
            latitude: 51.5074 + offset,
            longitude: -0.1278 + offset
        )
        session.addLocation(location)
    }
    
    return PhotoRouteOverlayView(session: session)
}
