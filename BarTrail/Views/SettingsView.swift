//
//  SettingsView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import SwiftUI

struct SettingsView: View {
    @StateObject private var autoStopManager = AutoStopManager.shared
    @StateObject private var storage = SessionStorage.shared
    @State private var showingClearDataAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Auto-Stop Settings
                Section {
                    Toggle("Auto-Stop After Long Sessions", isOn: $autoStopManager.isAutoStopEnabled)
                        .onChange(of: autoStopManager.isAutoStopEnabled) { _, _ in
                            autoStopManager.saveSettings()
                        }
                    
                    if autoStopManager.isAutoStopEnabled {
                        Stepper("Stop after \(autoStopManager.autoStopHours) hours", 
                               value: $autoStopManager.autoStopHours, 
                               in: 1...24)
                            .onChange(of: autoStopManager.autoStopHours) { _, _ in
                                autoStopManager.saveSettings()
                            }
                    }
                } header: {
                    Text("Auto-Stop")
                } footer: {
                    Text("Automatically stop tracking after the specified time to save battery.")
                }
                
                // Dwell Detection Settings
                Section {
                    HStack {
                        Text("Dwell Radius")
                        Spacer()
                        Text("25 meters")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Minimum Duration")
                        Spacer()
                        Text("20 minutes")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Dwell Detection")
                } footer: {
                    Text("A stop is detected when you stay within 25 meters for 20+ minutes.")
                }
                
                // Data Management
                Section {
                    HStack {
                        Text("Sessions Stored")
                        Spacer()
                        Text("\(storage.sessions.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showingClearDataAlert = true
                    } label: {
                        Text("Clear All History")
                    }
                } header: {
                    Text("Data")
                }
                
                // Privacy
                Section {
                    HStack {
                        Text("Location Data")
                        Spacer()
                        Text("Stored Locally")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Analytics")
                        Spacer()
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("BarTrail stores all data locally on your device. No data is sent to external servers.")
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.releaseVersionNumber ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))")
                            .foregroundColor(.secondary)
                    }
                    
//                    Link(destination: URL(string: "https://github.com")!) {
//                        HStack {
//                            Text("GitHub")
//                            Spacer()
//                            Image(systemName: "arrow.up.forward")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .alert("Clear All History?", isPresented: $showingClearDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    storage.clearAllSessions()
                }
            } message: {
                Text("This will permanently delete all \(storage.sessions.count) session(s). This action cannot be undone.")
            }
        }
    }
}

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

#Preview {
    SettingsView()
}
