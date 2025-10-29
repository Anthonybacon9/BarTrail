//
//  DetailedStatsView.swift
//  BarTrail
//
//  Created by Assistant
//

import SwiftUI
import MapKit

struct DetailedStatsView: View {
    @StateObject private var storage = SessionStorage.shared
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showUpgrade = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // FREE STATS SECTION
                    freeStatsSection()
                    
                    // PREMIUM STATS SECTION
                    premiumStatsSection()
                }
                .padding(.vertical)
            }
            .navigationTitle("Detailed Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showUpgrade) {
                PremiumUpgradeSheet()
            }
        }
    }
    
    // MARK: - Free Stats Section
    
    @ViewBuilder
    private func freeStatsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.title2.bold())
                .padding(.horizontal)
            
            // Total Nights Card
            StatCard(
                icon: "moon.stars.fill",
                title: "Total Nights Out",
                value: "\(storage.totalNights)",
                color: .purple,
                isFree: true
            )
            
            // Distance Stats
            StatCard(
                icon: "figure.walk",
                title: "Total Distance",
                value: formatDistance(storage.totalDistance),
                subtitle: "Avg: \(formatDistance(storage.averageNightDistance)) per night",
                color: .blue,
                isFree: true
            )
            
            // Time Stats
            StatCard(
                icon: "clock.fill",
                title: "Total Time",
                value: formatDuration(storage.totalDuration),
                subtitle: "Avg: \(formatDuration(storage.averageNightDuration)) per night",
                color: .green,
                isFree: true
            )
            
            // Stops Stats
            StatCard(
                icon: "mappin.circle.fill",
                title: "Total Stops",
                value: "\(storage.totalStops)",
                subtitle: "Avg: \(String(format: "%.1f", Double(storage.totalStops) / Double(max(storage.totalNights, 1)))) per night",
                color: .orange,
                isFree: true
            )
            
            // Current Streak
            let streak = storage.currentWeeklyStreak()
            StatCard(
                icon: "flame.fill",
                title: "Weekly Streak",
                value: "\(streak) day\(streak == 1 ? "" : "s")",
                subtitle: streak > 0 ? "Keep it going! 🎉" : "Start a new streak tonight",
                color: .red,
                isFree: true
            )
        }
    }
    
    // MARK: - Premium Stats Section
    
    @ViewBuilder
    private func premiumStatsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Premium Insights")
                    .font(.title2.bold())
                
                if !revenueCatManager.isSubscribed {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text("PREMIUM")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.orange.opacity(0.2))
                    )
                }
            }
            .padding(.horizontal)
            
            if revenueCatManager.isSubscribed {
                // Premium Stats - Full Access
                premiumStatsUnlocked()
            } else {
                // Premium Stats - Locked
                premiumStatsLocked()
            }
        }
    }
    
    // MARK: - Premium Stats (Unlocked)
    
    @ViewBuilder
    private func premiumStatsUnlocked() -> some View {
        // Drink Stats Section Header
        Text("🍻 Drink Statistics")
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 8)
        
        // Total Drinks This Year
        let yearlyDrinks = calculateYearlyDrinks()
        StatCard(
            icon: "calendar",
            title: "Drinks This Year",
            value: "\(yearlyDrinks.total)",
            subtitle: "Since Jan 1, \(Calendar.current.component(.year, from: Date()))",
            color: .purple,
            isFree: false
        )
        
        // Favorite Drink Type
        let favoriteDrink = calculateFavoriteDrink()
        StatCard(
            icon: "star.fill",
            title: "Favorite Drink",
            value: favoriteDrink.icon,
            subtitle: "\(favoriteDrink.name) - \(favoriteDrink.count) drinks",
            color: .pink,
            isFree: false
        )
        
        // Drink Breakdown Chart
        drinkBreakdownCard()
        
        // Average Drinks Per Night
        let avgDrinks = calculateAverageDrinksPerNight()
        StatCard(
            icon: "chart.bar.fill",
            title: "Avg Per Night",
            value: String(format: "%.1f", avgDrinks),
            subtitle: "drinks per night out",
            color: .teal,
            isFree: false
        )
        
        // Biggest Night (Most Drinks)
        if let biggestNight = storage.sessions.max(by: { $0.drinks.total < $1.drinks.total }), biggestNight.drinks.total > 0 {
            StatCard(
                icon: "flame.fill",
                title: "Biggest Night",
                value: "\(biggestNight.drinks.total) drinks",
                subtitle: biggestNight.startTime.formatted(date: .abbreviated, time: .omitted),
                color: .orange,
                isFree: false
            )
        }
        
        // Night Stats Section Header
        Text("📊 Night Records")
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 16)
        
        // Longest Night
        if let longestNight = storage.sessions.max(by: { ($0.duration ?? 0) < ($1.duration ?? 0) }) {
            StatCard(
                icon: "crown.fill",
                title: "Longest Night",
                value: formatDuration(longestNight.duration ?? 0),
                subtitle: longestNight.startTime.formatted(date: .abbreviated, time: .omitted),
                color: .yellow,
                isFree: false
            )
        }
        
        // Furthest Distance
        if let furthestNight = storage.sessions.max(by: { $0.totalDistance < $1.totalDistance }) {
            StatCard(
                icon: "arrow.up.right",
                title: "Furthest Night",
                value: formatDistance(furthestNight.totalDistance),
                subtitle: furthestNight.startTime.formatted(date: .abbreviated, time: .omitted),
                color: .cyan,
                isFree: false
            )
        }
        
        // Most Stops
        if let mostStops = storage.sessions.max(by: { $0.dwells.count < $1.dwells.count }) {
            StatCard(
                icon: "star.fill",
                title: "Most Stops",
                value: "\(mostStops.dwells.count)",
                subtitle: mostStops.startTime.formatted(date: .abbreviated, time: .omitted),
                color: .pink,
                isFree: false
            )
        }
        
        // Average Stop Duration
        let avgStopDuration = calculateAverageStopDuration()
        StatCard(
            icon: "timer",
            title: "Avg Stop Duration",
            value: formatDuration(avgStopDuration),
            subtitle: "Time spent at each location",
            color: .indigo,
            isFree: false
        )
        
        // Busiest Day of Week
        let busiestDay = calculateBusiestDayOfWeek()
        StatCard(
            icon: "calendar",
            title: "Favorite Day",
            value: busiestDay.day,
            subtitle: "\(busiestDay.count) nights",
            color: .teal,
            isFree: false
        )
        
        // Most Active Time
        let peakTime = calculatePeakTime()
        StatCard(
            icon: "clock.badge.checkmark",
            title: "Peak Activity Time",
            value: peakTime,
            subtitle: "Most common start time",
            color: .mint,
            isFree: false
        )
        
        // Patterns Section Header
        Text("📈 Activity Patterns")
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 16)
        
        // Recent Activity (Last 30 days)
        let recentSessions = storage.recentSessions(days: 30)
        StatCard(
            icon: "chart.line.uptrend.xyaxis",
            title: "Last 30 Days",
            value: "\(recentSessions.count) nights",
            subtitle: "Total: \(formatDistance(recentSessions.reduce(0) { $0 + $1.totalDistance }))",
            color: .purple,
            isFree: false
        )
        
        // Most Visited Area (based on dwell clustering)
        let hotSpot = calculateMostVisitedArea()
        StatCard(
            icon: "location.fill",
            title: "Favourite Spot",
            value: "\(hotSpot.visits) visits",
            subtitle: hotSpot.name,
            color: .red,
            isFree: false
        )
    }
    
    // MARK: - Premium Stats (Locked)
    
    @ViewBuilder
    private func premiumStatsLocked() -> some View {
        Button {
            showUpgrade = true
        } label: {
            VStack(spacing: 16) {
                // Blurred preview cards
                VStack(spacing: 12) {
                    // Drink stats preview
                    premiumLockedCard(icon: "calendar", title: "Drinks This Year", value: "XXX", color: .purple)
                    premiumLockedCard(icon: "star.fill", title: "Favorite Drink", value: "🍺", color: .pink)
                    
                    // Blurred drink breakdown
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "chart.pie.fill")
                                .foregroundColor(.blue)
                            Text("Drink Breakdown")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        ForEach(0..<3) { _ in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 20, height: 20)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 6)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    
                    premiumLockedCard(icon: "chart.bar.fill", title: "Avg Per Night", value: "X.X", color: .teal)
                    premiumLockedCard(icon: "crown.fill", title: "Longest Night", value: "XX:XX", color: .yellow)
                    premiumLockedCard(icon: "arrow.up.right", title: "Furthest Night", value: "XX.X km", color: .cyan)
                    premiumLockedCard(icon: "star.fill", title: "Most Stops", value: "XX", color: .pink)
                    premiumLockedCard(icon: "timer", title: "Avg Stop Duration", value: "XX:XX", color: .indigo)
                    premiumLockedCard(icon: "calendar", title: "Favorite Day", value: "XXXXX", color: .teal)
                }
                .blur(radius: 4)
                .overlay(
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "lock.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                            Text("Unlock Premium Insights")
                                .font(.title3.bold())
                            
                            Text("Get detailed analytics about your nights")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Feature list
                        VStack(alignment: .leading, spacing: 8) {
                            premiumFeatureRow(icon: "calendar", text: "Yearly drink statistics")
                            premiumFeatureRow(icon: "chart.pie.fill", text: "Drink type breakdown")
                            premiumFeatureRow(icon: "crown.fill", text: "Record-breaking stats")
                            premiumFeatureRow(icon: "calendar", text: "Activity patterns")
                            premiumFeatureRow(icon: "location.fill", text: "Favorite locations")
                            premiumFeatureRow(icon: "chart.line.uptrend.xyaxis", text: "Trend analysis")
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("Unlock with BarTrail+")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                                .foregroundColor(.orange)
                        }
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.barTrailPrimary, Color.barTrailSecondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.barTrailPrimary.opacity(0.4), radius: 10)
                    }
                    .padding()
                )
            }
            .padding(.horizontal)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func premiumLockedCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3.bold())
            }
            
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func premiumFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
    
    // MARK: - Stat Card Component
    
    @ViewBuilder
    private func drinkBreakdownCard() -> some View {
        let yearlyDrinks = calculateYearlyDrinks()
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Drink Breakdown")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            
            Divider()
            
            if yearlyDrinks.total > 0 {
                VStack(spacing: 8) {
                    if yearlyDrinks.beer > 0 {
                        drinkRow(icon: "🍺", name: "Beer", count: yearlyDrinks.beer, total: yearlyDrinks.total, color: .yellow)
                    }
                    if yearlyDrinks.spirits > 0 {
                        drinkRow(icon: "🥃", name: "Spirits", count: yearlyDrinks.spirits, total: yearlyDrinks.total, color: .orange)
                    }
                    if yearlyDrinks.cocktails > 0 {
                        drinkRow(icon: "🍹", name: "Cocktails", count: yearlyDrinks.cocktails, total: yearlyDrinks.total, color: .pink)
                    }
                    if yearlyDrinks.shots > 0 {
                        drinkRow(icon: "🥃", name: "Shots", count: yearlyDrinks.shots, total: yearlyDrinks.total, color: .red)
                    }
                    if yearlyDrinks.wine > 0 {
                        drinkRow(icon: "🍷", name: "Wine", count: yearlyDrinks.wine, total: yearlyDrinks.total, color: .purple)
                    }
                    if yearlyDrinks.other > 0 {
                        drinkRow(icon: "🍻", name: "Other", count: yearlyDrinks.other, total: yearlyDrinks.total, color: .blue)
                    }
                }
            } else {
                Text("No drinks tracked yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func drinkRow(icon: String, name: String, count: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.bold())
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geometry.size.width * CGFloat(count) / CGFloat(total), height: 6)
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(Double(count) / Double(total) * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stat Card Component
    
    @ViewBuilder
    private func StatCard(icon: String, title: String, value: String, subtitle: String? = nil, color: Color, isFree: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title2.bold())
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !isFree {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    // MARK: - Calculation Methods
    
    private func calculateYearlyDrinks() -> DrinkCount {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        
        let yearSessions = storage.sessions.filter { session in
            calendar.component(.year, from: session.startTime) == currentYear
        }
        
        var yearlyTotal = DrinkCount()
        for session in yearSessions {
            yearlyTotal.beer += session.drinks.beer
            yearlyTotal.spirits += session.drinks.spirits
            yearlyTotal.cocktails += session.drinks.cocktails
            yearlyTotal.shots += session.drinks.shots
            yearlyTotal.wine += session.drinks.wine
            yearlyTotal.other += session.drinks.other
        }
        
        return yearlyTotal
    }
    
    private func calculateFavoriteDrink() -> (name: String, count: Int, icon: String) {
        let yearlyDrinks = calculateYearlyDrinks()
        
        let drinkCounts = [
            ("Beer", yearlyDrinks.beer, "🍺"),
            ("Spirits", yearlyDrinks.spirits, "🥃"),
            ("Cocktails", yearlyDrinks.cocktails, "🍹"),
            ("Shots", yearlyDrinks.shots, "🥃"),
            ("Wine", yearlyDrinks.wine, "🍷"),
            ("Other", yearlyDrinks.other, "🍻")
        ]
        
        if let favorite = drinkCounts.max(by: { $0.1 < $1.1 }), favorite.1 > 0 {
            return (favorite.0, favorite.1, favorite.2)
        }
        
        return ("None yet", 0, "🍻")
    }
    
    private func calculateAverageDrinksPerNight() -> Double {
        guard !storage.sessions.isEmpty else { return 0 }
        
        let totalDrinks = storage.sessions.reduce(0) { $0 + $1.drinks.total }
        return Double(totalDrinks) / Double(storage.sessions.count)
    }
    
    // MARK: - Calculation Methods
    
    private func calculateAverageStopDuration() -> TimeInterval {
        let allDwells = storage.sessions.flatMap { $0.dwells }
        
        guard !allDwells.isEmpty else {
            return 0
        }
        
        // Filter out invalid dwells
        let validDwells = allDwells.filter { dwell in
            let duration = dwell.duration
            
            // Must be positive
            guard duration > 0 else { return false }
            
            // Must be less than 12 hours (reasonable max for a single stop)
            guard duration <= 43200 else { return false }
            
            // End time must be in the past or very recent future (within 1 day)
            let now = Date()
            let maxEndTime = now.addingTimeInterval(86400) // 1 day from now
            guard dwell.endTime <= maxEndTime else { return false }
            
            // Start time must be before end time (should always be true, but double check)
            guard dwell.startTime < dwell.endTime else { return false }
            
            return true
        }
        
        guard !validDwells.isEmpty else {
            print("⚠️ No valid dwells found after filtering")
            return 0
        }
        
        let totalDuration = validDwells.reduce(0.0) { $0 + $1.duration }
        let average = totalDuration / Double(validDwells.count)
        
        print("✅ Calculated average stop duration: \(average) seconds from \(validDwells.count)/\(allDwells.count) valid dwells")
        
        return average
    }
    
    private func calculateBusiestDayOfWeek() -> (day: String, count: Int) {
        let calendar = Calendar.current
        var dayCounts: [Int: Int] = [:]
        
        for session in storage.sessions {
            let weekday = calendar.component(.weekday, from: session.startTime)
            dayCounts[weekday, default: 0] += 1
        }
        
        guard let busiest = dayCounts.max(by: { $0.value < $1.value }) else {
            return ("N/A", 0)
        }
        
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return (dayNames[busiest.key - 1], busiest.value)
    }
    
    private func calculatePeakTime() -> String {
        guard !storage.sessions.isEmpty else { return "N/A" }
        
        let calendar = Calendar.current
        let hours = storage.sessions.map { calendar.component(.hour, from: $0.startTime) }
        
        // Find most common hour
        var hourCounts: [Int: Int] = [:]
        for hour in hours {
            hourCounts[hour, default: 0] += 1
        }
        
        guard let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key else {
            return "N/A"
        }
        
        // Format as time range
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        
        var components = DateComponents()
        components.hour = peakHour
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(peakHour):00"
    }
    
    private func calculateMostVisitedArea() -> (visits: Int, name: String) {
        let allDwells = storage.sessions.flatMap { $0.dwells }
        guard !allDwells.isEmpty else { return (0, "No data yet") }
        
        // Cluster dwells by proximity (within 100m)
        var clusters: [[DwellPoint]] = []
        var processedDwells: Set<UUID> = []
        
        for dwell in allDwells {
            guard !processedDwells.contains(dwell.id) else { continue }
            
            var cluster: [DwellPoint] = [dwell]
            processedDwells.insert(dwell.id)
            
            for otherDwell in allDwells {
                guard !processedDwells.contains(otherDwell.id) else { continue }
                
                let distance = CLLocation(
                    latitude: dwell.location.latitude,
                    longitude: dwell.location.longitude
                ).distance(from: CLLocation(
                    latitude: otherDwell.location.latitude,
                    longitude: otherDwell.location.longitude
                ))
                
                if distance <= 100 {
                    cluster.append(otherDwell)
                    processedDwells.insert(otherDwell.id)
                }
            }
            
            clusters.append(cluster)
        }
        
        // Find largest cluster
        guard let biggestCluster = clusters.max(by: { $0.count < $1.count }) else {
            return (0, "No data yet")
        }
        
        // Get the most common place name from the cluster
        var placeNameCounts: [String: Int] = [:]
        
        for dwell in biggestCluster {
            if let displayName = dwell.displayName, !displayName.isEmpty {
                placeNameCounts[displayName, default: 0] += 1
            }
        }
        
        // If we have named places, use the most common one
        if let mostCommonPlace = placeNameCounts.max(by: { $0.value < $1.value }) {
            return (biggestCluster.count, mostCommonPlace.key)
        }
        
        // Fallback: If no places are named, return a generic location description
        let centerDwell = biggestCluster[0]
        return (biggestCluster.count, "Unnamed location (\(biggestCluster.count) visits)")
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
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}

