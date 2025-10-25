
import SwiftUI
import CoreLocation
import Combine

let startPhrases = [
    "Start the night \(readyEmoji.randomElement() ?? "🫡")",
    "Get the pints in \(readyEmoji.randomElement() ?? "🫡")",
    "Kick off the crawl \(readyEmoji.randomElement() ?? "🫡")",
    "Hit the town \(readyEmoji.randomElement() ?? "🫡")",
    "Get Started \(readyEmoji.randomElement() ?? "🫡")"
]

let readyPhrases = [
    "Ready to Track \(readyEmoji.randomElement() ?? "🫡")",
    "Whenever you're ready \(readyEmoji.randomElement() ?? "🫡")",
    "When you say go \(readyEmoji.randomElement() ?? "🫡")",
    "Pre-drinks are done? Let’s roll \(readyEmoji.randomElement() ?? "🍻")",
    "Where’s the first stop? \(readyEmoji.randomElement() ?? "🍹")",
    "Night’s young - let’s track it \(readyEmoji.randomElement() ?? "🌃")",
    "You know the drill \(readyEmoji.randomElement() ?? "😎")",
    "Ready when you are \(readyEmoji.randomElement() ?? "👊")",
    "Round one? \(readyEmoji.randomElement() ?? "🍺")",
    "Let’s hit the trail \(readyEmoji.randomElement() ?? "🥂")",
    "Time to cause some stories \(readyEmoji.randomElement() ?? "📍")",
    "Let’s see where the night goes \(readyEmoji.randomElement() ?? "🌙")",
    "Another one for the books \(readyEmoji.randomElement() ?? "📖")",
    "Start the chaos \(readyEmoji.randomElement() ?? "🔥")",
    "We're locked and loaded \(readyEmoji.randomElement() ?? "🔒")",
    "Spin up the trail \(readyEmoji.randomElement() ?? "🌀")",
    "Own Your Night \(readyEmoji.randomElement() ?? "🫡")"
]

let readyEmoji = [
    "🤝",
    "🫡",
    "😎",
    "🍻",
    "🍹",
    "🌙",
    "🥂",
    "🔥",
    "🎉",
    "📍",
    "🍺"
]

struct ContentView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var showingPermissionAlert = false
    @State private var showingSummary = false
    @State private var selectedTab = 0
    @State private var showCelebration = false
    @State private var isTitleAnimating = true
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Tab
            homeView()
                .tabItem {
                    Label("Track", systemImage: "location.circle.fill")
                    //                    Image(systemName: "location.circle.fill")
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
        .accentColor(Color.barTrailSecondary)
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
                    colors: [Color.barTrailPrimary.opacity(0.3), Color.barTrailSecondary.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if showCelebration {
                    TemporaryFireworks(duration: 4.0)
                        .allowsHitTesting(false) // Allow taps to pass through
                        .transition(.opacity)
                        .ignoresSafeArea()
                }
                
                VStack(spacing: 24) {
                    // Top status bar (like "Location: Always ✓")
                    authorizationStatusView()
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    
                    
                    // Status Display
                    if sessionManager.isTracking, let session = sessionManager.currentSession {
                        sessionStatusCard(session: session)
                    } else if let lastSession = sessionManager.currentSession, !lastSession.isActive {
                        completedSessionCard(session: lastSession)
                    } else {
                        VStack(spacing: 8) {
                            Text(sessionManager.isTracking ? "Night in Progress" : "\(readyPhrases.randomElement() ?? "Ready to Track")")
                                .font(Font.custom("Poppins-Bold", size: 32))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .multilineTextAlignment(.center) // Center align when wrapped
                                .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
                                .lineLimit(1) // Optional: Limit to 2 lines max
                                .minimumScaleFactor(0.5) // Optional: Scale down if needed
                                .frame(width: 300)
                            
                            Text(sessionManager.isTracking ? "Tracking your route..." : "Hit start to begin your night 🍻")
                                .font(Font.custom("Poppins-Light", size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Main Button (huge & curved, like NRC Start Run)
                    actionButton()
                        .padding(.horizontal, 32)
                    //                        .padding(.bottom, 24)
                    
                }
                .padding(.vertical)
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
            
            Text("Tap below when you head out")
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
            
//            Button {
//                showingSummary = true
//            } label: {
//                HStack {
//                    Image(systemName: "map.fill")
//                    Text("View Map")
//                }
//                .font(.subheadline.bold())
//                .foregroundColor(.white)
//                .frame(maxWidth: .infinity)
//                .padding(.vertical, 12)
//                .background(
//                    LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
//                )
//                .cornerRadius(12)
//            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cornerRadius(20)
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private func actionButton() -> some View {
        if sessionManager.isTracking {
            // Stop Night button
            BarTrail.actionButton(action: handleMainAction, color: Color.red, color2: nil, text: "Stop Night", img: nil)
        } else if let session = sessionManager.currentSession, !session.isActive {
            // View Map + Start New Night buttons
            VStack(spacing: 12) {
                BarTrail.actionButton(action: showMapEnable, color: Color.teal, color2: nil, text: "Show Map 🗺️", img: nil)
                
                BarTrail.actionButton(action: handleMainAction, color: Color.barTrailSecondary, color2: nil, text: "Start New Night 🥳", img: nil)
            }
        } else {
            // Start Night button
            BarTrail.actionButton(action: handleMainAction, color: Color.barTrailPrimary, color2: nil, text: "\(startPhrases.randomElement() ?? "Start")", img: nil)
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
                .font(Font.custom("Poppins-Regular", size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func handleMainAction() {
        if sessionManager.isTracking {
            sessionManager.stopNight()
            // Optionally show celebration when stopping too
            // showCelebration = true
        } else {
            let status = sessionManager.authorizationStatus
            
            if status == .notDetermined {
                sessionManager.requestLocationPermission()
            } else if status == .denied || status == .restricted {
                showingPermissionAlert = true
            } else {
                sessionManager.startNight()
                // Show celebration when starting the night
                withAnimation(.easeIn(duration: 0.3)) {
                    showCelebration = true
                }
                
                // Auto-hide after celebration duration
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showCelebration = false
                    }
                }
            }
        }
    }
    
    private func showMapEnable() {
        showingSummary = true
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

// MARK: - Custom Thinking Animation for BarTrail
struct ThinkingBarTrail: View {
    @State private var thinking: Bool = false
    let letters = Array("BarTrail")
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<letters.count, id: \.self) { index in
                Text(String(letters[index]))
                    .font(Font.custom("BBHSansBogle-Regular", size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .hueRotation(.degrees(thinking ? 45 : 0))
                    .opacity(thinking ? 0.8 : 1)
                    .scaleEffect(thinking ? 0.95 : 1.05)
                    .offset(y: thinking ? 0 : 2)
                    .animation(
                        .easeInOut(duration: 1.0)
                        .delay(0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) / 10),
                        value: thinking
                    )
            }
        }
        .shadow(color: Color.barTrailSecondary.opacity(0.6), radius: 10, x: 0, y: 0)
        .onAppear {
            thinking = true
        }
    }
}

struct actionButton: View {
    let action: () -> Void
    let color: Color
    let color2: Color?
    let text: String
    let img: String?
    
    var body: some View {
        GeometryReader { geometry in
            Button(action: action) {
                if #available(iOS 26.0, *) {
                    HStack {
                        Text(text)
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassEffect(.regular.tint(color/*.opacity(0.5)*/))
                    .shadow(color: color.opacity(0.4), radius: 10)
                } else {
                    HStack {
                        Text(text)
                            .font(.title3.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(colors: [color, color2 ?? Color.barTrailSecondary], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: color.opacity(0.4), radius: 10)
                }
            }
            .frame(width: geometry.size.width * 0.81)
            .frame(maxWidth: .infinity) // Center the button
        }
        .frame(height: 60) // Set a fixed height for GeometryReader
    }
}

//// MARK: - Original Thinking Component (for reference or other uses)
//struct Thinking: View {
//    @State private var counter: Int = 0
//    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
//    @State private var thinking: Bool = false
//    let letters = Array("Evaluating Sentence")
//
//    var body: some View {
//        HStack {
//            Image(systemName: "sparkles")
//                .font(.title)
//                .foregroundStyle(EllipticalGradient(colors:[.blue, .indigo], center: .center, startRadiusFraction: 0.0, endRadiusFraction: 0.5))
//                .phaseAnimator([false, true]) { content, phase in
//                    content
//                        .symbolEffect(.breathe.byLayer, value: phase)
//                }
//
//            HStack(spacing: 0) {
//                ForEach(0..<letters.count, id: \.self) { index in
//                    Text(String(letters[index]))
//                        .foregroundStyle(.blue)
//                        .hueRotation(.degrees(thinking ? 220 : 0))
//                        .opacity(thinking ? 0 : 1)
//                        .scaleEffect(x: thinking ? 0.75 : 1, y: thinking ? 1.25 : 1, anchor: .bottom)
//                        .animation(.easeInOut(duration: 0.5).delay(1).repeatForever(autoreverses: false).delay(Double(index) / 20), value: thinking)
//                }
//            }
//        }
//        .onAppear {
//            thinking = true
//        }
//    }
//}

// MARK: - Temporary Fireworks Wrapper
struct TemporaryFireworks: View {
    let duration: Double
    @State private var isActive = true
    
    var body: some View {
        ZStack {
            if isActive {
                ParticleEmitterView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            isActive = false
                        }
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
