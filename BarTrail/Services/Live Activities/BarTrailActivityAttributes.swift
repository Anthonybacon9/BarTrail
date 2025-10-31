//
//  BarTrailActivityAttributes.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//

import ActivityKit
import Foundation
import SwiftUI
import Combine

// MARK: - Activity Attributes

struct BarTrailActivityAttributes: ActivityAttributes {
    // Static data that doesn't change during the activity
    public struct ContentState: Codable, Hashable {
        var startTime: Date
        var currentDistance: Double // in meters
        var currentStops: Int
        var currentDrinks: Int // NEW
        var elapsedTime: TimeInterval
        var lastUpdateTime: Date
    }
    
    // Identifier for this tracking session
    var sessionId: String
}

// MARK: - Live Activity Manager

class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    
    @Published var currentActivity: Activity<BarTrailActivityAttributes>?
    
    // Track last update to avoid excessive updates
        private var lastUpdateTime: Date?
        private var lastDistance: Double = 0
        private var lastStops: Int = 0
        private var lastDrinks: Int = 0
    
    private init() {}
    
    
    
    // MARK: - Start Live Activity
    
    func startActivity(sessionId: String, startTime: Date) {
        // Check iOS version
        if #available(iOS 16.2, *) {
            // Check if Live Activities are supported and enabled
            let authInfo = ActivityAuthorizationInfo()
            print("🔍 Live Activity authorization status: \(authInfo.areActivitiesEnabled)")
            
            guard authInfo.areActivitiesEnabled else {
                print("⚠️ Live Activities are not enabled. Enable in Settings → BarTrail → Live Activities")
                return
            }
            
            let attributes = BarTrailActivityAttributes(sessionId: sessionId)
            let initialState = BarTrailActivityAttributes.ContentState(
                startTime: startTime,
                currentDistance: 0,
                currentStops: 0,
                currentDrinks: 0,
                elapsedTime: 0,
                lastUpdateTime: Date()
            )
            
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: nil),
                    pushType: nil
                )
                
                currentActivity = activity
                print("✅ Live Activity started: \(activity.id)")
                print("📱 Activity state: \(activity.activityState)")
            } catch {
                print("❌ Failed to start Live Activity: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
            }
        } else {
            print("⚠️ Live Activities require iOS 16.2+")
        }
    }
    
    // MARK: - Update Live Activity
    
    func updateActivity(distance: Double, stops: Int, drinks: Int, elapsedTime: TimeInterval) {
            guard let activity = currentActivity else {
                print("⚠️ No active Live Activity to update")
                return
            }
            
            // Only update if something meaningful changed
            let distanceChanged = abs(distance - lastDistance) >= 50  // 50+ meters
            let stopsChanged = stops != lastStops
            let drinksChanged = drinks != lastDrinks
            
            // Or if it's been 2+ minutes since last update
            let timeSinceLastUpdate = lastUpdateTime?.timeIntervalSinceNow ?? -999
            let timeForUpdate = timeSinceLastUpdate < -120  // 2 minutes
            
            guard distanceChanged || stopsChanged || drinksChanged || timeForUpdate else {
                // print("⏭️ Skipping Live Activity update (no significant changes)")
                return
            }
            
            Task {
                let updatedState = BarTrailActivityAttributes.ContentState(
                    startTime: activity.content.state.startTime,
                    currentDistance: distance,
                    currentStops: stops,
                    currentDrinks: drinks,
                    elapsedTime: elapsedTime,
                    lastUpdateTime: Date()
                )
                
                await activity.update(
                    ActivityContent(
                        state: updatedState,
                        staleDate: Date().addingTimeInterval(180) // Stale after 3 minutes (was 1)
                    )
                )
                
                // Update tracking
                lastDistance = distance
                lastStops = stops
                lastDrinks = drinks
                lastUpdateTime = Date()
                
                print("📱 Live Activity updated: \(formatDistance(distance)), \(stops) stops, \(drinks) drinks, \(formatDuration(elapsedTime))")
            }
        }
    
    // MARK: - End Live Activity (UPDATED - immediately dismisses)
    
    func endActivity(finalDistance: Double, finalStops: Int, finalDrinks: Int, duration: TimeInterval) {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to end")
            return
        }
        
        Task {
            let finalState = BarTrailActivityAttributes.ContentState(
                startTime: activity.content.state.startTime,
                currentDistance: finalDistance,
                currentStops: finalStops,
                currentDrinks: finalDrinks,
                elapsedTime: duration,
                lastUpdateTime: Date()
            )
            
            // End immediately after showing final state
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),
                dismissalPolicy: .immediate // CHANGED: Dismisses right away
            )
            
            currentActivity = nil
            print("🛑 Live Activity ended and dismissed")
        }
    }
    
    // MARK: - Helper
    
    private func formatDistance(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
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
}
