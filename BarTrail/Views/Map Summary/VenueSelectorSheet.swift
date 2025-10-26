import SwiftUI
import CoreLocation

struct VenueSelectorSheet: View {
    let dwell: DwellPoint
    @Binding var selectedVenueName: String?
    @Environment(\.dismiss) var dismiss
    
    @State private var nearbyVenues: [GeocodingService.VenueOption] = []
    @State private var isLoading = true
    @State private var customName = ""
    @State private var showCustomInput = false
    
    @State private var currentDisplayName: String = "Unknown Location"
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.purple)
                            
                            Text("Select Venue")
                                .font(.title2.bold())
                            
                            Text("Choose the correct location for this stop")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top)
                        
                        // Current Selection
                        GroupBox {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        Text(currentDisplayName)
                                            .font(.headline)
                                        
                                        if dwell.isManuallySet {
                                            Image(systemName: "pencil.circle.fill")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if dwell.isManuallySet {
                                    Button(role: .destructive) {
                                        selectedVenueName = nil
                                        dismiss()
                                    } label: {
                                        Text("Reset")
                                            .font(.caption.bold())
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        Divider()
                        
                        // Nearby Venues List
                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Finding nearby venues...")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if nearbyVenues.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text("No nearby venues found")
                                    .font(.headline)
                                Text("Try entering a custom name below")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Nearby Venues")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(nearbyVenues) { venue in
                                    Button {
                                        selectedVenueName = venue.name
                                        dismiss()
                                    } label: {
                                        VenueRow(
                                            venue: venue,
                                            isSelected: venue.name == currentDisplayName
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.top)
                        
                        // Custom Name Input
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation {
                                    showCustomInput.toggle()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Enter Custom Name")
                                        .font(.headline)
                                    Spacer()
                                    Image(systemName: showCustomInput ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            if showCustomInput {
                                VStack(spacing: 12) {
                                    TextField("Enter venue name", text: $customName)
                                        .textFieldStyle(.roundedBorder)
                                        .autocapitalization(.words)
                                    
                                    Button {
                                        guard !customName.isEmpty else { return }
                                        selectedVenueName = customName
                                        dismiss()
                                    } label: {
                                        Text("Save Custom Name")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(customName.isEmpty ? Color.gray : Color.blue)
                                            .cornerRadius(12)
                                    }
                                    .disabled(customName.isEmpty)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 30)
                }
                
                // Loading overlay for initial load
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // Load current display name
            if let displayName = dwell.displayName {
                currentDisplayName = displayName
            } else {
                // Fetch it if not already loaded
                if let fetchedName = await GeocodingService.shared.getBestVenueName(for: dwell.location) {
                    currentDisplayName = fetchedName
                }
            }
            
            await loadNearbyVenues()
        }
    }
    
    private func loadNearbyVenues() async {
        isLoading = true
        nearbyVenues = await GeocodingService.shared.getNearbyVenues(for: dwell.location, radius: 150)
        isLoading = false
    }
}

// MARK: - Venue Row Component

struct VenueRow: View {
    let venue: GeocodingService.VenueOption
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isSelected ? "checkmark" : categoryIcon)
                    .foregroundColor(isSelected ? .white : .secondary)
                    .font(.system(size: 18))
            }
            
            // Venue Info
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    if let category = venue.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(venue.formattedDistance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Chevron
            if !isSelected {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
        )
        .padding(.horizontal)
    }
    
    private var categoryIcon: String {
        guard let category = venue.category?.lowercased() else {
            return "mappin.circle"
        }
        
        if category.contains("bar") || category.contains("pub") {
            return "wineglass"
        } else if category.contains("restaurant") || category.contains("food") {
            return "fork.knife"
        } else if category.contains("cafe") || category.contains("coffee") {
            return "cup.and.saucer"
        } else if category.contains("club") || category.contains("night") {
            return "music.note"
        } else if category.contains("hotel") {
            return "bed.double"
        } else {
            return "building.2"
        }
    }
}

// MARK: - Preview

#Preview {
    let dwell = DwellPoint(
        location: CLLocationCoordinate2D(latitude: 53.40420426605551, longitude: -2.9807664346635425),
        startTime: Date().addingTimeInterval(-3600),
        endTime: Date()
    )
    
    return VenueSelectorSheet(
        dwell: dwell,
        selectedVenueName: .constant(nil)
    )
}
