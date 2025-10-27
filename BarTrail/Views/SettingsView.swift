//
//  SettingsView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var autoStopManager = AutoStopManager.shared
    @StateObject private var storage = SessionStorage.shared
    @StateObject private var mapStyleManager = MapStyleManager.shared
    @State private var showingClearDataAlert = false
    @State private var showingFeedbackSheet = false
    @State private var showingImportPicker = false
    @State private var showingImportSuccess = false
    @State private var showingImportError = false
    @State private var importErrorMessage = ""
    @State private var importedSessionDate = ""
    
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
                
                Section {
                    Picker("Map Style", selection: $mapStyleManager.selectedStyle) {
                        ForEach(MapStyleType.allCases) { style in
                            HStack {
                                Image(systemName: style.icon)
                                Text(style.rawValue)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    
                    if let currentStyle = MapStyleType(rawValue: mapStyleManager.selectedStyle.rawValue) {
                        Text(currentStyle.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Map Appearance")
                } footer: {
                    Text("Choose how the map appears in your night summaries.")
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
                    
                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("Import Session", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(role: .destructive) {
                        showingClearDataAlert = true
                    } label: {
                        Text("Clear All History")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Import previously exported JSON session files.")
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
                
                // Feedback Section
                Section {
                    Button {
                        showingFeedbackSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Send Feedback")
                            Spacer()
                        }
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("Share your ideas, report issues, or let us know what you think!")
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.releaseVersionNumber ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))")
                            .foregroundColor(.secondary)
                    }
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
            .alert("Import Successful", isPresented: $showingImportSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Session from \(importedSessionDate) has been imported successfully!")
            }
            .alert("Import Failed", isPresented: $showingImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importErrorMessage)
            }
            .sheet(isPresented: $showingFeedbackSheet) {
                FeedbackView()
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
        }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importErrorMessage = "No file was selected."
                showingImportError = true
                return
            }
            
            importSession(from: url)
            
        case .failure(let error):
            importErrorMessage = "Failed to access file: \(error.localizedDescription)"
            showingImportError = true
        }
    }
    
    private func importSession(from url: URL) {
        do {
            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Could not access the selected file."
                showingImportError = true
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Read the file data
            let data = try Data(contentsOf: url)
            
            // Decode the session
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let session = try decoder.decode(NightSession.self, from: data)
            
            // Check if session already exists
            if storage.sessions.contains(where: { $0.id == session.id }) {
                importErrorMessage = "This session has already been imported."
                showingImportError = true
                return
            }
            
            // Save the imported session
            storage.saveSession(session)
            
            // Show success message
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            importedSessionDate = dateFormatter.string(from: session.startTime)
            showingImportSuccess = true
            
            print("✅ Session imported successfully: \(session.id)")
            
        } catch DecodingError.dataCorrupted(let context) {
            importErrorMessage = "Invalid JSON file format: \(context.debugDescription)"
            showingImportError = true
        } catch DecodingError.keyNotFound(let key, _) {
            importErrorMessage = "Missing required field: \(key.stringValue)"
            showingImportError = true
        } catch DecodingError.typeMismatch(_, let context) {
            importErrorMessage = "Invalid data type in JSON: \(context.debugDescription)"
            showingImportError = true
        } catch {
            importErrorMessage = "Failed to import session: \(error.localizedDescription)"
            showingImportError = true
        }
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType: FeedbackType = .suggestion
    @State private var feedbackText = ""
    @State private var showingMailError = false
    
    enum FeedbackType: String, CaseIterable {
        case bug = "Bug Report"
        case suggestion = "Suggestion"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .bug: return "ladybug"
            case .suggestion: return "lightbulb"
            case .other: return "ellipsis.message"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            HStack {
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Feedback Type")
                }
                
                Section {
                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 150)
                } header: {
                    Text("Your Feedback")
                } footer: {
                    Text("Please be as detailed as possible. Include steps to reproduce if reporting a bug.")
                }
                
                Section {
                    Button {
                        sendFeedback()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Send Feedback")
                            Spacer()
                        }
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Email Not Available", isPresented: $showingMailError) {
                Button("OK") { }
            } message: {
                Text("Please ensure you have Mail configured on your device, or contact us at your-email@example.com")
            }
        }
    }
    
    private func sendFeedback() {
        let deviceInfo = """
        
        ---
        Device Info:
        iOS: \(UIDevice.current.systemVersion)
        Model: \(UIDevice.current.model)
        App Version: \(Bundle.main.releaseVersionNumber ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))
        """
        
        let subject = "BarTrail \(feedbackType.rawValue)"
        let body = feedbackText + deviceInfo
        
        if let emailURL = createEmailURL(subject: subject, body: body) {
            if UIApplication.shared.canOpenURL(emailURL) {
                UIApplication.shared.open(emailURL) { success in
                    if success {
                        dismiss()
                    } else {
                        showingMailError = true
                    }
                }
            } else {
                showingMailError = true
            }
        }
    }
    
    private func createEmailURL(subject: String, body: String) -> URL? {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Replace with your email address
        let urlString = "mailto:anthony.bacon@abcstech.co.uk?subject=\(subjectEncoded)&body=\(bodyEncoded)"
        
        return URL(string: urlString)
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

#Preview("Feedback View") {
    FeedbackView()
}
