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
                    
                    Button {
                        shareMapScreenshot()
                    } label: {
                        Label("Share Map Screenshot", systemImage: "map")
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
        
        shareContent(items: [text])
    }
    
    // MARK: - Export as JSON
    
    private func exportAsJSON() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        do {
            let jsonData = try encoder.encode(session)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Create temporary file
                let fileName = "bartrail_session_\(session.startTime.formatted(date: .numeric, time: .omitted)).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                
                try jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
                
                shareContent(items: [tempURL])
            }
        } catch {
            print("❌ Failed to encode session: \(error)")
        }
    }
    
    // MARK: - Share Map Screenshot
    
    private func shareMapScreenshot() {
        // Note: This is a placeholder. In a real app, you'd render the map to an image
        // For now, we'll share text with coordinates
        var text = "🗺️ BarTrail Route\n\n"
        
        if let first = session.route.first {
            text += "Start: \(String(format: "%.4f, %.4f", first.coordinate.latitude, first.coordinate.longitude))\n"
        }
        
        if let last = session.route.last {
            text += "End: \(String(format: "%.4f, %.4f", last.coordinate.latitude, last.coordinate.longitude))\n"
        }
        
        text += "\nView in Maps:\n"
        if let first = session.route.first {
            let mapsURL = "https://maps.apple.com/?q=\(first.coordinate.latitude),\(first.coordinate.longitude)"
            text += mapsURL
        }
        
        shareContent(items: [text])
    }
    
    // MARK: - Helper Methods
    
    private func shareContent(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // For iPad
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        rootViewController.present(activityVC, animated: true)
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