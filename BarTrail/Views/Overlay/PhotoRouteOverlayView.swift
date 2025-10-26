import SwiftUI
import PhotosUI

struct PhotoRouteOverlayView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var routeOverlay: UIImage?
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
    
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        NavigationView {
            ZStack {
                if let baseImage = selectedImage {
                    GeometryReader { geometry in
                        let baseImageAspect = (selectedImage?.size.width ?? 1) / (selectedImage?.size.height ?? 1)
                        let viewAspect = geometry.size.width / geometry.size.height
                        
                        let actualDisplaySize: CGSize = {
                            if baseImageAspect > viewAspect {
                                return CGSize(
                                    width: geometry.size.width,
                                    height: geometry.size.width / baseImageAspect
                                )
                            } else {
                                return CGSize(
                                    width: geometry.size.height * baseImageAspect,
                                    height: geometry.size.height
                                )
                            }
                        }()
                        
                        ZStack {
                            Image(uiImage: baseImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: actualDisplaySize.width, height: actualDisplaySize.height)
                            
                            if let overlay = routeOverlay {
                                Image(uiImage: overlay)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: actualDisplaySize.width, height: actualDisplaySize.height)
                                    .opacity(overlayOpacity)
                                    .scaleEffect(overlayScale)
                                    .offset(overlayOffset)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                overlayOffset = CGSize(
                                                    width: value.translation.width,
                                                    height: value.translation.height
                                                )
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
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            viewSize = actualDisplaySize
                        }
                        .onChange(of: geometry.size) { _, _ in
                            let newDisplaySize: CGSize
                            if baseImageAspect > viewAspect {
                                newDisplaySize = CGSize(
                                    width: geometry.size.width,
                                    height: geometry.size.width / baseImageAspect
                                )
                            } else {
                                newDisplaySize = CGSize(
                                    width: geometry.size.height * baseImageAspect,
                                    height: geometry.size.height
                                )
                            }
                            viewSize = newDisplaySize
                        }
                    }
                    .ignoresSafeArea()
                    
                    VStack {
                        Spacer()
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
        }
        .onAppear {
            loadPlaceNames()
            generateRouteOverlay()
        }
    }
    
    // MARK: - Generate Composite
    
    private func generateAndShareComposite() {
        guard let baseImage = selectedImage,
              let overlay = routeOverlay else { return }
        
        isGeneratingComposite = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let imageSize = baseImage.size
            
            let overlayAspect = overlay.size.width / overlay.size.height
            let viewAspect = viewSize.width / viewSize.height
            
            var overlayDisplaySize = viewSize
            if overlayAspect > viewAspect {
                overlayDisplaySize.height = viewSize.width / overlayAspect
            } else {
                overlayDisplaySize.width = viewSize.height * overlayAspect
            }
            
            let overlayScaleFactor = overlay.size.width / overlayDisplaySize.width
            
            let overlayImageOffset = CGSize(
                width: overlayOffset.width * overlayScaleFactor,
                height: overlayOffset.height * overlayScaleFactor
            )
            
            let baseScaleFactor = imageSize.width / viewSize.width
            let finalOverlaySize = CGSize(
                width: overlay.size.width * overlayScale * baseScaleFactor / overlayScaleFactor,
                height: overlay.size.height * overlayScale * baseScaleFactor / overlayScaleFactor
            )
            
            let renderer = UIGraphicsImageRenderer(size: imageSize)
                    
            let composite = renderer.image { context in
                baseImage.draw(in: CGRect(origin: .zero, size: imageSize))
                
                let overlayOrigin = CGPoint(
                    x: (imageSize.width - finalOverlaySize.width) / 2 + (overlayImageOffset.width * baseScaleFactor),
                    y: (imageSize.height - finalOverlaySize.height) / 2 + (overlayImageOffset.height * baseScaleFactor)
                )
                
                let overlayRect = CGRect(origin: overlayOrigin, size: finalOverlaySize)
                
                overlay.draw(in: overlayRect, blendMode: .normal, alpha: overlayOpacity)
                
                drawWatermark(in: context, size: imageSize)
            }
            
            UIImageWriteToSavedPhotosAlbum(composite, nil, nil, nil)
            
            DispatchQueue.main.async {
                self.compositeImage = composite
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
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(watermarkOpacity),
            .strokeColor: UIColor.black.withAlphaComponent(watermarkOpacity * 0.7),
            .strokeWidth: -1.0
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let padding: CGFloat = 20
        
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
                Image(systemName: "opacity")
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
            
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
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
    
    // MARK: - Generate Route Overlay (FIXED)
    
    private func generateRouteOverlay() {
        DispatchQueue.global(qos: .userInitiated).async {
            // FIXED: Pass dwellPlaceNames to respect manual selections
            if let overlay = RouteOverlayGenerator.shared.generateRouteWithOutline(
                from: session,
                placeNames: dwellPlaceNames
            ) {
                DispatchQueue.main.async {
                    self.routeOverlay = overlay
                }
            }
        }
    }
    
    // MARK: - Load Photo
    
    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    self.selectedImage = image
                    self.selectedPhoto = nil
                }
            }
        }
    }
    
    // MARK: - Load Place Names (FIXED TO RESPECT MANUAL SELECTIONS)

    private func loadPlaceNames() {
        Task {
            for dwell in session.dwells {
                // FIXED: Use displayName which respects manual override
                if let displayName = dwell.displayName {
                    await MainActor.run {
                        dwellPlaceNames[dwell.id] = displayName
                    }
                } else {
                    // Only fetch if no name exists at all
                    if let placeName = await GeocodingService.shared.getBestVenueName(for: dwell.location) {
                        await MainActor.run {
                            dwellPlaceNames[dwell.id] = placeName
                        }
                    }
                }
            }
            // Regenerate overlay once place names are loaded
            await MainActor.run {
                generateRouteOverlay()
            }
        }
    }
}

// MARK: - Photo Thumbnail
struct PhotoThumbnail: View {
    let photo: PhotosPickerItem
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            Group {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
        }
        .task {
            await loadThumbnail()
        }
    }
    
    private func loadThumbnail() async {
        if let data = try? await photo.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run {
                self.thumbnailImage = image
            }
        }
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
