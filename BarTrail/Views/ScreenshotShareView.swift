//
//  ScreenshotShareView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//
import SwiftUI

// MARK: - Screenshot Share View
struct ScreenshotShareView: View {
    let image: UIImage
    let session: NightSession
    let onDismiss: () -> Void
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Screenshot Preview
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding()
                    
                    // Session Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Session Summary")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            statItem(icon: "clock.fill", label: "Duration", value: formatDuration(session.duration ?? 0))
                            statItem(icon: "figure.walk", label: "Distance", value: formatDistance(session.totalDistance))
                            statItem(icon: "mappin.circle.fill", label: "Stops", value: "\(session.dwells.count)")
                        }
                        
                        Text("Captured on \(Date().formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            shareScreenshot()
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Screenshot")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        
                        Button {
                            saveToPhotos()
                        } label: {
                            HStack {
                                Image(systemName: "photo")
                                Text("Save to Photos")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Map Screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: [image])
            }
        }
    }
    
    private func shareScreenshot() {
        showingShareSheet = true
    }
    
    private func saveToPhotos() {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        // Show confirmation (you might want to add a proper alert here)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    private func formatDistance(_ distance: Double) -> String {
        distance >= 1000 ? 
            String(format: "%.2f km", distance / 1000) : 
            String(format: "%.0f m", distance)
    }
}


