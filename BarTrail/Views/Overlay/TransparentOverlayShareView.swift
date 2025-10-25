//
//  TransparentOverlayShareView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 25/10/2025.
//


import SwiftUI
import UIKit
import Photos

struct TransparentOverlayShareView: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var showSaveSuccess = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .background(
                        // Checkerboard pattern to show transparency
                        Image(systemName: "checkerboard.rectangle")
                            .resizable()
                            .foregroundColor(.gray.opacity(0.2))
                    )
                    .cornerRadius(12)
                    .padding()
                
                Text("Transparent Route Overlay")
                    .font(.headline)
                
                Text("Use this transparent overlay on your own photos or videos")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        saveToPhotos()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        shareImage()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Route Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Saved to Photos", isPresented: $showSaveSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your transparent route overlay has been saved to your photo library.")
            }
        }
    }
    
    private func saveToPhotos() {
        guard let pngData = image.pngData() else {
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: pngData, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.showSaveSuccess = true
                    }
                }
            }
        }
    }
    
    private func shareImage() {
        guard let pngData = image.pngData() else { return }
        
        // Create a temporary file URL for the PNG
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("route-overlay.png")
        
        do {
            try pngData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController {
                
                var currentVC = rootVC
                while let presentedVC = currentVC.presentedViewController {
                    currentVC = presentedVC
                }
                
                activityVC.popoverPresentationController?.sourceView = currentVC.view
                currentVC.present(activityVC, animated: true)
            }
        } catch {
            print("Error writing PNG: \(error)")
        }
    }
}
