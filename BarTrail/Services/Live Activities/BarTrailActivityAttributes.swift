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
    
    func updateActivity(distance: Double, stops: Int, elapsedTime: TimeInterval) {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to update")
            return
        }
        
        Task {
            let updatedState = BarTrailActivityAttributes.ContentState(
                startTime: activity.content.state.startTime,
                currentDistance: distance,
                currentStops: stops,
                elapsedTime: elapsedTime,
                lastUpdateTime: Date()
            )
            
            await activity.update(
                ActivityContent(
                    state: updatedState,
                    staleDate: Date().addingTimeInterval(60) // Stale after 1 minute
                )
            )
            
            print("📱 Live Activity updated: \(formatDistance(distance)), \(stops) stops, \(formatDuration(elapsedTime))")
        }
    }
    
    // MARK: - End Live Activity
    
    func endActivity(finalDistance: Double, finalStops: Int, duration: TimeInterval) {
        guard let activity = currentActivity else {
            print("⚠️ No active Live Activity to end")
            return
        }
        
        Task {
            let finalState = BarTrailActivityAttributes.ContentState(
                startTime: activity.content.state.startTime,
                currentDistance: finalDistance,
                currentStops: finalStops,
                elapsedTime: duration,
                lastUpdateTime: Date()
            )
            
            // End with final content (stays visible for a few seconds)
            await activity.end(
                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),
                dismissalPolicy: .default
            )
            
            currentActivity = nil
            print("🛑 Live Activity ended")
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
