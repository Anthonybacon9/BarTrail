import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingPermissionAlert = false
    @State private var showingSummary = false
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            homeView()
                .tabItem {
                    Label("Track", systemImage: "location.circle.fill")
                }
                .tag(0)
            
            // History Tab
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
                .tag(1)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .onAppear {
            // Request notification permission on first launch
            if !notificationManager.isAuthorized {
                notificationManager.requestAuthorization()
            }
        }
    }
    
    // MARK: - Home View
    
    @ViewBuilder
    private func homeView() -> some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 8) {
                        Text("BarTrail")
                            .font(.system(size: 44, weight: .bold))
                        Text("Track your night out")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    Spacer()
                    
                    // Status Display
                    if sessionManager.isTracking, let session = sessionManager.currentSession {
                        sessionStatusCard(session: session)
                    } else if let lastSession = sessionManager.currentSession, !lastSession.isActive {
                        completedSessionCard(session: lastSession)
                    } else {
                        readyStatusCard()
                    }
                    
                    Spacer()
                    
                    // Main Action Button
                    actionButton()
                    
                    // Authorization Status
                    authorizationStatusView()
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("BarTrail needs 'Always' location access to track your night in the background. Please enable it in Settings.")
            }
            .sheet(isPresented: $showingSummary) {
                if let session = sessionManager.currentSession {
                    MapSummaryView(session: session)
                }
            }
        }
    }
    
    // MARK: - Status Cards
    
    @ViewBuilder
    private func sessionStatusCard(session: NightSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "location.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
                .symbolEffect(.pulse)
            
            Text("Night in Progress")
                .font(.title2.bold())
            
            VStack(spacing: 8) {
                HStack {
                    Text("Started:")
                    Spacer()
                    Text(session.startTime, style: .time)
                }
                HStack {
                    Text("Duration:")
                    Spacer()
                    if let duration = session.duration {
                        Text(formatDuration(duration))
                    }
                }
                HStack {
                    Text("Distance:")
                    Spacer()
                    Text(formatDistance(session.totalDistance))
                }
                HStack {
                    Text("Locations:")
                    Spacer()
                    Text("\(session.route.count)")
                }
                HStack {
                    Text("Stops:")
                    Spacer()
                    Text("\(session.dwells.count)")
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
    
    @ViewBuilder
    private func readyStatusCard() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 50))
                .foregroundColor(.yellow)
            
            Text("Ready to Track")
                .font(.title2.bold())
            
            Text("Tap 'Start Night' when you head out")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
    
    @ViewBuilder
    private func completedSessionCard(session: NightSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Night Complete!")
                .font(.title2.bold())
            
            VStack(spacing: 8) {
                HStack {
                    Text("Duration:")
                    Spacer()
                    if let duration = session.duration {
                        Text(formatDuration(duration))
                    }
                }
                HStack {
                    Text("Distance:")
                    Spacer()
                    Text(formatDistance(session.totalDistance))
                }
                HStack {
                    Text("Stops:")
                    Spacer()
                    Text("\(session.dwells.count)")
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            
            Button {
                showingSummary = true
            } label: {
                HStack {
                    Image(systemName: "map.fill")
                    Text("View Map")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(12)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.15))
        .cornerRadius(20)
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private func actionButton() -> some View {
        if sessionManager.isTracking {
            // Stop Night button
            Button(action: handleMainAction) {
                HStack {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                    Text("Stop Night")
                        .font(.title3.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: .red.opacity(0.4), radius: 10)
            }
        } else if let session = sessionManager.currentSession, !session.isActive {
            // View Map + Start New Night buttons
            VStack(spacing: 12) {
                Button {
                    showingSummary = true
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                            .font(.title3)
                        Text("View Map")
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: .green.opacity(0.4), radius: 10)
                }
                
                Button(action: handleMainAction) {
                    HStack {
                        Image(systemName: "play.fill")
                            .font(.title3)
                        Text("Start New Night")
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.4), radius: 10)
                }
            }
        } else {
            // Start Night button
            Button(action: handleMainAction) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Start Night")
                        .font(.title3.bold())
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.4), radius: 10)
            }
        }
    }
    
    // MARK: - Authorization Status
    
    @ViewBuilder
    private func authorizationStatusView() -> some View {
        let status = sessionManager.authorizationStatus
        
        Group {
            switch status {
            case .notDetermined:
                statusHStack(text: "Location: Not Set", color: .gray)
            case .authorizedAlways:
                statusHStack(text: "Location: Always ✓", color: .green)
            case .authorizedWhenInUse:
                statusHStack(text: "Location: When In Use ⚠️", color: .orange)
            case .denied, .restricted:
                statusHStack(text: "Location: Denied ✕", color: .red)
            @unknown default:
                statusHStack(text: "Location: Unknown", color: .gray)
            }
        }
    }

    private func statusHStack(text: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func handleMainAction() {
        if sessionManager.isTracking {
            sessionManager.stopNight()
        } else {
            let status = sessionManager.authorizationStatus
            
            if status == .notDetermined {
                sessionManager.requestLocationPermission()
            } else if status == .denied || status == .restricted {
                showingPermissionAlert = true
            } else {
                sessionManager.startNight()
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
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
    ContentView()
}
