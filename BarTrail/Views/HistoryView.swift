//
//  HistoryView.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import SwiftUI
import MapKit

struct HistoryView: View {
    @StateObject private var storage = SessionStorage.shared
    @State private var selectedSession: NightSession?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: NightSession?
    
    var body: some View {
        NavigationView {
            ZStack {
                if storage.sessions.isEmpty {
                    emptyStateView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Weekly Stats Card
                            weeklyStatsCard()
                            
                            // All Time Stats Card
                            allTimeStatsCard()
                            
                            // Sessions List
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Nights")
                                    .font(.title2.bold())
                                    .padding(.horizontal)
                                
                                ForEach(storage.sessions) { session in
                                    SessionHistoryCard(session: session)
                                        .onTapGesture {
                                            selectedSession = session
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                sessionToDelete = session
                                                showingDeleteAlert = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.vertical)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !storage.sessions.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showingDeleteAlert = true
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                MapSummaryView(session: session)
            }
            .alert("Delete Session?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        storage.deleteSession(session)
                    } else {
                        storage.clearAllSessions()
                    }
                    sessionToDelete = nil
                }
            } message: {
                if sessionToDelete != nil {
                    Text("This session will be permanently deleted.")
                } else {
                    Text("All session history will be permanently deleted.")
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.stars")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Nights Yet")
                .font(.title2.bold())
            
            Text("Your tracked nights will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Weekly Stats Card
    
    @ViewBuilder
    private func weeklyStatsCard() -> some View {
        let weekSessions = storage.sessionsThisWeek()
        let weekDistance = weekSessions.reduce(0.0) { $0 + $1.totalDistance }
        let weekDuration = weekSessions.compactMap { $0.duration }.reduce(0, +)
        let weekStops = weekSessions.reduce(0) { $0 + $1.dwells.count }
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.circle.fill")
                    .foregroundColor(.blue)
                Text("This Week")
                    .font(.headline)
                Spacer()
                Text("\(weekSessions.count) nights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if !weekSessions.isEmpty {
                Divider()
                
                HStack(spacing: 20) {
                    statColumn(icon: "figure.walk", value: formatDistance(weekDistance), label: "Distance")
                    statColumn(icon: "clock", value: formatDuration(weekDuration), label: "Time")
                    statColumn(icon: "mappin.circle", value: "\(weekStops)", label: "Stops")
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    // MARK: - All Time Stats Card
    
    @ViewBuilder
    private func allTimeStatsCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.purple)
                Text("All Time")
                    .font(.headline)
                Spacer()
                Text("\(storage.totalNights) nights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            HStack(spacing: 20) {
                statColumn(icon: "figure.walk", value: formatDistance(storage.totalDistance), label: "Distance")
                statColumn(icon: "clock", value: formatDuration(storage.totalDuration), label: "Time")
                statColumn(icon: "mappin.circle", value: "\(storage.totalStops)", label: "Stops")
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avg. Night")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(storage.averageNightDuration))
                        .font(.subheadline.bold())
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Avg. Distance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDistance(storage.averageNightDistance))
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func statColumn(icon: String, value: String, label: String) -> some View {
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

// MARK: - Session History Card

struct SessionHistoryCard: View {
    let session: NightSession
    
    var body: some View {
        HStack(spacing: 16) {
            // Mini Map Preview (placeholder)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                
                VStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("\(session.dwells.count)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Text("stops")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Session Info
            VStack(alignment: .leading, spacing: 6) {
                Text(session.startTime, style: .date)
                    .font(.headline)
                
                Text(session.startTime, style: .time)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label(formatDuration(session.duration ?? 0), systemImage: "clock")
                    Label(formatDistance(session.totalDistance), systemImage: "figure.walk")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
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
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}

#Preview {
    HistoryView()
}