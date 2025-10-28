
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
    @State private var showingRatingSheet = false
    
    @State private var updateTimer: Timer?
    
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
                // Clean white/system background (Strava style)
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                
                if showCelebration {
                    TemporaryFireworks(duration: 4.0)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .ignoresSafeArea()
                }
                
                VStack(spacing: 0) {
                    // Top status bar
                    authorizationStatusView()
                        .padding(.top, 20)
                        .padding(.horizontal)
                    
                    if sessionManager.isTracking, let session = sessionManager.currentSession {
                        // LIVE TRACKING VIEW (Strava style)
                        stravaStyleLiveTracking(session: session)
                    } else if let lastSession = sessionManager.currentSession, !lastSession.isActive {
                        // COMPLETED SESSION
                        stravaStyleCompletedSession(session: lastSession)
                    } else {
                        // READY TO START
                        stravaStyleReadyView()
                    }
                }
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
            .sheet(isPresented: $showingRatingSheet) {
                if let session = sessionManager.currentSession {
                    NightRatingSheet(session: session) { rating in
                        session.setRating(rating)
                        SessionStorage.shared.saveSession(session)
                        print("⭐ Night rated: \(rating) stars")
                    }
                }
            }
            .onAppear {
                startLiveUpdates()
            }
            .onDisappear {
                stopLiveUpdates()
            }
        }
    }
    
    @ViewBuilder
    private func stravaStyleLiveTracking(session: NightSession) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero stat - Duration (big and bold)
                VStack(spacing: 4) {
                    Text(formatDuration(session.duration ?? 0))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                }
                .padding(.top, 40)
                .padding(.bottom, 32)
                
                // Stats Grid (Strava-style)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 24) {
                    statBox(
                        value: formatDistance(session.totalDistance),
                        label: "Distance",
                        icon: "figure.walk",
                        color: .blue
                    )
                    
                    statBox(
                        value: "\(session.dwells.count)",
                        label: "Stops",
                        icon: "mappin.circle.fill",
                        color: .purple
                    )
                    
                    statBox(
                        value: "\(session.route.count)",
                        label: "Locations",
                        icon: "location.fill",
                        color: .green
                    )
                    
                    statBox(
                        value: "\(session.drinks.total)",
                        label: "Drinks",
                        icon: "🍺",
                        color: .orange,
                        isEmoji: true
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                
                // Divider
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .padding(.horizontal, 24)
                
                // Drink Counter Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                        Text("Add Drinks")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    stravaStyleDrinkButtons(session: session)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 100) // Space for button
            }
        }
        .overlay(alignment: .bottom) {
                BarTrail.actionButton(action: handleMainAction, color: .red, color2: nil, text: "✋ Finish Night", img: nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private func stravaStyleCompletedSession(session: NightSession) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                // Celebration Header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.bounce, value: session.endTime)
                    
                    Text("Night Complete!")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text(formatTimeRange(start: session.startTime, end: session.endTime ?? Date()))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Stats Summary
                VStack(spacing: 16) {
                    summaryStatRow(
                        icon: "clock.fill",
                        label: "Duration",
                        value: formatDuration(session.duration ?? 0),
                        color: .blue
                    )
                    
                    summaryStatRow(
                        icon: "figure.walk",
                        label: "Distance",
                        value: formatDistance(session.totalDistance),
                        color: .green
                    )
                    
                    summaryStatRow(
                        icon: "mappin.circle.fill",
                        label: "Stops",
                        value: "\(session.dwells.count) locations",
                        color: .purple
                    )
                    
                    if session.drinks.total > 0 {
                        summaryStatRow(
                            icon: "wineglass.fill",
                            label: "Drinks",
                            value: "\(session.drinks.total) total",
                            color: .orange
                        )
                    }
                }
                .padding(.horizontal, 24)
                
                // Action Buttons
                VStack(spacing: 12) {
                    BarTrail.actionButton(action: showMapEnable, color: .green, color2: nil, text: "Show Summary", img: nil)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                    
                    BarTrail.actionButton(action: handleMainAction, color: Color.barTrailPrimary, color2: nil, text: "Start New Session 🫡", img: nil)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
        }
    }
    
    @ViewBuilder
    private func stravaStyleReadyView() -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.barTrailPrimary.opacity(0.2),
                                    Color.barTrailSecondary.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Fun title (keeping your personality)
                Text(readyPhrases.randomElement() ?? "Ready to Track")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 32)
                
                Text("Track your night out, see your route, and remember the good times")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            
            Spacer()
            
            // Start Button
            BarTrail.actionButton(action: handleMainAction, color: Color.barTrailPrimary, color2: nil, text: "\(startPhrases.randomElement() ?? "Start")", img: nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private func statBox(value: String, label: String, icon: String, color: Color, isEmoji: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            VStack(spacing: 12) {
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(color)
                }
                
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .glassEffect(.regular.tint(.barTrailPrimary.opacity(0.3)), in: .rect(cornerRadius: 16))
        } else {
            VStack(spacing: 12) {
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(color)
                }
                
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }

    @ViewBuilder
    private func summaryStatRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Text(value)
                    .font(.headline)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func stravaStyleDrinkButtons(session: NightSession) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(DrinkType.allCases, id: \.self) { drinkType in
                stravaStyleDrinkButton(for: drinkType, session: session)
            }
        }
    }

    @ViewBuilder
    private func stravaStyleDrinkButton(for type: DrinkType, session: NightSession) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                session.addDrink(type: type)
                SessionStorage.shared.saveSession(session)
            }
            
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        } label: {
            VStack(spacing: 8) {
                // Icon with badge
                ZStack(alignment: .topTrailing) {
                    Text(type.icon)
                        .font(.system(size: 32))
                    
                    if getDrinkCount(for: type, session: session) > 0 {
                        Text("\(getDrinkCount(for: type, session: session))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                
                Text(type.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        getDrinkCount(for: type, session: session) > 0 ? Color.orange : Color.clear,
                        lineWidth: 2
                    )
            )
        }
    }

    
//    @ViewBuilder
//    private func homeView() -> some View {
//        NavigationView {
//            ZStack {
//                // Background gradient
//                LinearGradient(
//                    colors: [Color.barTrailPrimary.opacity(0.3), Color.barTrailSecondary.opacity(0.3)],
//                    startPoint: .topLeading,
//                    endPoint: .bottomTrailing
//                )
//                .ignoresSafeArea()
//                
//                if showCelebration {
//                    TemporaryFireworks(duration: 4.0)
//                        .allowsHitTesting(false) // Allow taps to pass through
//                        .transition(.opacity)
//                        .ignoresSafeArea()
//                }
//                
//                VStack(spacing: 24) {
//                    // Top status bar (like "Location: Always ✓")
//                    authorizationStatusView()
//                        .padding(.top, 20)
//                    
//                    Spacer()
//                    
//                    
//                    
//                    // Status Display
//                    if sessionManager.isTracking, let session = sessionManager.currentSession {
//                        sessionStatusCard(session: session)
//                    } else if let lastSession = sessionManager.currentSession, !lastSession.isActive {
//                        completedSessionCard(session: lastSession)
//                    } else {
//                        VStack(spacing: 8) {
//                            Text(sessionManager.isTracking ? "Night in Progress" : "\(readyPhrases.randomElement() ?? "Ready to Track")")
//                                .font(Font.custom("Poppins-Bold", size: 32))
//                                .foregroundStyle(
//                                    LinearGradient(colors: [Color.barTrailPrimary, Color.barTrailSecondary],
//                                                   startPoint: .leading, endPoint: .trailing)
//                                )
//                                .multilineTextAlignment(.center) // Center align when wrapped
//                                .fixedSize(horizontal: false, vertical: true) // Allow vertical expansion
//                                .lineLimit(1) // Optional: Limit to 2 lines max
//                                .minimumScaleFactor(0.5) // Optional: Scale down if needed
//                                .frame(width: 300)
//                            
//                            Text(sessionManager.isTracking ? "Tracking your route..." : "Hit start to begin your night 🍻")
//                                .font(Font.custom("Poppins-Light", size: 14))
//                                .foregroundColor(.secondary)
//                        }
//                    }
//                    
//                    Spacer()
//                    
//                    // Main Button (huge & curved, like NRC Start Run)
//                    actionButton()
//                        .padding(.horizontal, 32)
//                    //                        .padding(.bottom, 24)
//                    
//                }
//                .padding(.vertical)
//            }
//            .navigationBarHidden(true)
//            .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
//                Button("Open Settings") {
//                    if let url = URL(string: UIApplication.openSettingsURLString) {
//                        UIApplication.shared.open(url)
//                    }
//                }
//                Button("Cancel", role: .cancel) { }
//            } message: {
//                Text("BarTrail needs 'Always' location access to track your night in the background. Please enable it in Settings.")
//            }
//            .sheet(isPresented: $showingSummary) {
//                if let session = sessionManager.currentSession {
//                    MapSummaryView(session: session)
//                }
//            }
//            .sheet(isPresented: $showingRatingSheet) {
//                if let session = sessionManager.currentSession {
//                    NightRatingSheet(session: session) { rating in
//                        session.setRating(rating)
//                        SessionStorage.shared.saveSession(session)
//                        print("⭐ Night rated: \(rating) stars")
//                    }
//                }
//            }
//            .onAppear {
//                startLiveUpdates()
//            }
//            .onDisappear {
//                stopLiveUpdates()
//            }
//        }
//    }
    
    // MARK: - Status Cards
    
//    @ViewBuilder
//    private func sessionStatusCard(session: NightSession) -> some View {
//        VStack(spacing: 16) {
//            Image(systemName: "location.fill")
//                .font(.system(size: 50))
//                .foregroundColor(.green)
//                .symbolEffect(.pulse)
//            
//            Text("Night in Progress")
//                .font(.title2.bold())
//            
//            VStack(spacing: 8) {
//                HStack {
//                    Text("Started:")
//                    Spacer()
//                    Text(session.startTime, style: .time)
//                }
//                HStack {
//                    Text("Duration:")
//                    Spacer()
//                    if let duration = session.duration {
//                        Text(formatDuration(duration))
//                    }
//                }
//                HStack {
//                    Text("Distance:")
//                    Spacer()
//                    Text(formatDistance(session.totalDistance))
//                }
//                HStack {
//                    Text("Stops:")
//                    Spacer()
//                    Text("\(session.dwells.count)")
//                }
//                
//                // NEW: Total drinks count
//                if session.drinks.total > 0 {
//                    HStack {
//                        Text("Drinks:")
//                        Spacer()
//                        Text("\(session.drinks.total)")
//                            .foregroundColor(.orange)
//                    }
//                }
//            }
//            .font(.subheadline)
//            .padding()
//            .background(Color.white.opacity(0.1))
//            .cornerRadius(12)
//            
//            // NEW: Drink counter buttons
//            drinkCounterButtons(session: session)
//        }
//        .padding()
//        .frame(maxWidth: .infinity)
//        .cornerRadius(20)
//    }

    // NEW: Add this function after sessionStatusCard
    @ViewBuilder
    private func drinkCounterButtons(session: NightSession) -> some View {
        VStack(spacing: 12) {
            Text("Add Drinks")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(DrinkType.allCases, id: \.self) { drinkType in
                    drinkButton(for: drinkType, session: session)
                }
            }
        }
        .padding(.top, 8)
    }

    // NEW: Add this function after drinkCounterButtons
    @ViewBuilder
    private func drinkButton(for type: DrinkType, session: NightSession) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                session.addDrink(type: type)
                SessionStorage.shared.saveSession(session) // Save immediately
            }
            
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Text(type.icon)
                    .font(.title2)
                
                Text(type.rawValue)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                // Count badge
                if getDrinkCount(for: type, session: session) > 0 {
                    Text("\(getDrinkCount(for: type, session: session))")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // NEW: Helper function to get drink count
    private func getDrinkCount(for type: DrinkType, session: NightSession) -> Int {
        switch type {
        case .beer: return session.drinks.beer
        case .spirits: return session.drinks.spirits
        case .cocktails: return session.drinks.cocktails
        case .shots: return session.drinks.shots
        case .wine: return session.drinks.wine
        case .other: return session.drinks.other
        }
    }
    
    
    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
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
                if session.drinks.total > 0 {
                    HStack {
                        Text("Drinks:")
                        Spacer()
                        Text("\(session.drinks.total)")
                            .foregroundColor(.orange)
                    }
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
    
//    @ViewBuilder
//    private func actionButton() -> some View {
//        if sessionManager.isTracking {
//            // Stop Night button
//            BarTrail.actionButton(action: handleMainAction, color: Color.red, color2: nil, text: "Stop Night", img: nil)
//        } else if let session = sessionManager.currentSession, !session.isActive {
//            // View Map + Start New Night buttons
//            VStack() {
//                if #available(iOS 26.0, *) {
//                    GlassEffectContainer {
//                        BarTrail.actionButton(action: showMapEnable, color: Color.teal, color2: nil, text: "Show Map 🗺️", img: nil)
//                        
//                        BarTrail.actionButton(action: handleMainAction, color: Color.barTrailSecondary, color2: nil, text: "Start New Night 🥳", img: nil)
//                    }
//                } else {
//                    BarTrail.actionButton(action: showMapEnable, color: Color.teal, color2: nil, text: "Show Map 🗺️", img: nil)
//                    BarTrail.actionButton(action: handleMainAction, color: Color.barTrailSecondary, color2: nil, text: "Start New Night 🥳", img: nil)
//                }
//            }
//        } else {
//            // Start Night button
//            BarTrail.actionButton(action: handleMainAction, color: Color.barTrailPrimary, color2: nil, text: "\(startPhrases.randomElement() ?? "Start")", img: nil)
//        }
//    }
    
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
            stopLiveUpdates() // Stop timer when night ends
            // Show rating sheet after stopping
            showingRatingSheet = true
        } else {
            let status = sessionManager.authorizationStatus
            
            if status == .notDetermined {
                sessionManager.requestLocationPermission()
            } else if status == .denied || status == .restricted {
                showingPermissionAlert = true
            } else {
                sessionManager.startNight()
                startLiveUpdates() // Start timer when night begins
                withAnimation(.easeIn(duration: 0.3)) {
                    showCelebration = true
                }
                
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
    
    private func startLiveUpdates() {
        // Only start timer if tracking
        guard sessionManager.isTracking else { return }
        
        // Update every second
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Force UI refresh by sending objectWillChange
            sessionManager.objectWillChange.send()
        }
    }

    private func stopLiveUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
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
                    .glassEffect(.regular.tint(color.opacity(0.3)))
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
