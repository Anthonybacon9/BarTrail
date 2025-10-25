//
//  SessionStorage.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import Foundation
import CoreLocation
import Combine

class SessionStorage: ObservableObject {
    static let shared = SessionStorage()
    
    @Published var sessions: [NightSession] = []
    
    private let storageKey = "bartrail_sessions"
    
    private init() {
        loadSessions()
    }
    
    // MARK: - Storage Operations
    
    func saveSession(_ session: NightSession) {
        // Add to array if not already present
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.append(session)
        } else {
            // Update existing session
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            }
        }
        
        // Sort by start time (newest first)
        sessions.sort { $0.startTime > $1.startTime }
        
        saveSessions()
        
        print("💾 Session saved: \(session.id)")
    }
    
    func deleteSession(_ session: NightSession) {
        sessions.removeAll { $0.id == session.id }
        saveSessions()
        print("🗑️ Session deleted: \(session.id)")
    }
    
    func clearAllSessions() {
        sessions.removeAll()
        saveSessions()
        print("🗑️ All sessions cleared")
    }
    
    // Get days of the week (0-6, Monday-Sunday) that have sessions this week
    func daysWithSessionsThisWeek() -> [Int] {
        let calendar = Calendar.current
        // Get the start of the current week (Monday)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekSessions = sessions.filter { $0.startTime >= weekStart }
        
        var days: [Int] = []
        for session in weekSessions {
            // Convert to 0-6 where 0=Monday, 6=Sunday
            var dayOfWeek = calendar.component(.weekday, from: session.startTime) - 2
            if dayOfWeek < 0 {
                dayOfWeek = 6 // Sunday becomes 6
            }
            if !days.contains(dayOfWeek) {
                days.append(dayOfWeek)
            }
        }
        
        return days.sorted()
    }
    
    // Calculate current weekly streak (consecutive days with sessions this week)
    func currentWeeklyStreak() -> Int {
        let daysWithSessions = daysWithSessionsThisWeek()
        let calendar = Calendar.current
        
        // Convert current day to 0-6 where 0=Monday, 6=Sunday
        var today = calendar.component(.weekday, from: Date()) - 2
        if today < 0 {
            today = 6 // Sunday becomes 6
        }
        
        // If today has a session, start counting from today
        // Otherwise, start from yesterday
        let startDay = daysWithSessions.contains(today) ? today : today - 1
        
        var streak = 0
        var currentDay = startDay
        
        // Count backwards until we find a day without a session
        while currentDay >= 0 && daysWithSessions.contains(currentDay) {
            streak += 1
            currentDay -= 1
        }
        
        return streak
    }
    
    // Helper method to get the start of week (Monday)
    func startOfWeek() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return calendar.date(from: components) ?? Date()
    }
    
    
    // MARK: - Persistence
    
    private func saveSessions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("💾 Saved \(sessions.count) sessions to storage")
        } catch {
            print("❌ Failed to save sessions: \(error)")
        }
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            print("📂 No saved sessions found")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            sessions = try decoder.decode([NightSession].self, from: data)
            print("📂 Loaded \(sessions.count) sessions from storage")
        } catch {
            print("❌ Failed to load sessions: \(error)")
            sessions = []
        }
    }
    
    // MARK: - Statistics
    
    var totalNights: Int {
        sessions.count
    }
    
    var totalDistance: CLLocationDistance {
        sessions.reduce(0) { $0 + $1.totalDistance }
    }
    
    var totalDuration: TimeInterval {
        sessions.compactMap { $0.duration }.reduce(0, +)
    }
    
    var totalStops: Int {
        sessions.reduce(0) { $0 + $1.dwells.count }
    }
    
    var averageNightDuration: TimeInterval {
        guard !sessions.isEmpty else { return 0 }
        return totalDuration / Double(sessions.count)
    }
    
    var averageNightDistance: CLLocationDistance {
        guard !sessions.isEmpty else { return 0 }
        return totalDistance / Double(sessions.count)
    }
    
    // Get sessions from last N days
    func recentSessions(days: Int) -> [NightSession] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sessions.filter { $0.startTime >= cutoffDate }
    }
    
    // Get sessions from a specific week
    func sessionsThisWeek() -> [NightSession] {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return sessions.filter { $0.startTime >= weekStart }
    }
}
