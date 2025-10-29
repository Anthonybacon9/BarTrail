//
//  SessionShareView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 23/10/2025.
//


import SwiftUI
import MapKit

struct SessionShareView: View {
    let session: NightSession
    @Environment(\.dismiss) var dismiss
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            List {
                Section("Export Options") {
                    Button {
                        shareAsText()
                    } label: {
                        Label("Share Summary as Text", systemImage: "text.quote")
                    }
                    
                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "doc.text")
                    }
                }
                
                Section("Session Details") {
                    HStack {
                        Text("Date")
                        Spacer()
                        Text(session.startTime, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(formatDuration(session.duration ?? 0))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(formatDistance(session.totalDistance))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Stops")
                        Spacer()
                        Text("\(session.dwells.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Locations Tracked")
                        Spacer()
                        Text("\(session.route.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Share Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareItems)
                    .id(UUID()) // Force sheet recreation
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Share as Text
    private func shareAsText() {
        let duration = session.duration ?? 0
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let distance = session.totalDistance
        let distanceText = distance >= 1000 ?
            String(format: "%.2f km", distance / 1000) :
            String(format: "%.0f m", distance)
        
        var text = "🌙 BarTrail Night Summary\n\n"
        text += "📅 Date: \(session.startTime.formatted(date: .long, time: .shortened))\n"
        
        if hours > 0 {
            text += "⏱️ Duration: \(hours)h \(minutes)m\n"
        } else {
            text += "⏱️ Duration: \(minutes)m\n"
        }
        
        text += "📏 Distance: \(distanceText)\n"
        text += "📍 Stops: \(session.dwells.count)\n\n"
        
        if !session.dwells.isEmpty {
            text += "Stop Details:\n"
            for (index, dwell) in session.dwells.enumerated() {
                let dwellMinutes = Int(dwell.duration) / 60
                text += "\(index + 1). \(dwell.startTime.formatted(date: .omitted, time: .shortened)) - \(dwellMinutes) minutes\n"
            }
        }
        
        shareItems = [text]
        showingShareSheet = true
    }
    
    // MARK: - Export as JSON
    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(session)
            
            // Create filename
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let dateString = dateFormatter.string(from: session.startTime)
            let fileName = "bartrail_session_\(dateString).json"
            
            // Get Documents directory
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not access documents directory"])
            }
            
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            // Write file
            try jsonData.write(to: fileURL)
            
            // Verify file was created
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw NSError(domain: "FileError", code: -2, userInfo: [NSLocalizedDescriptionKey: "File was not created successfully"])
            }
            
            print("File created at: \(fileURL.path)")
            
            shareItems = [fileURL]
            showingShareSheet = true
            
        } catch {
            errorMessage = "Failed to export session data: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func shareMapScreenshot() {
        // For now, direct users to use the screenshot feature from the map view
        let text = "📱 Use the 'Capture Screenshot' option in the map view to share a high-quality image of your route with statistics."
        shareItems = [text]
        showingShareSheet = true
    }
    
    // MARK: - Helper Methods
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
}

// MARK: - Share Sheet Wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

#Preview {
    let session = NightSession()
    session.endTime = Date()
    
    // Add mock data
    for i in 0..<10 {
        let offset = Double(i) * 0.001
        let location = CLLocation(
            latitude: 51.5074 + offset,
            longitude: -0.1278 + offset
        )
        session.addLocation(location)
    }
    
    session.addDwell(DwellPoint(
        location: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
        startTime: Date().addingTimeInterval(-3600),
        endTime: Date().addingTimeInterval(-2400)
    ))
    
    return SessionShareView(session: session)
}
