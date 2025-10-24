//
//  BarTrailWidgetsLiveActivity.swift
//  BarTrailWidgets
//
//  Created by Anthony Bacon on 24/10/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct BarTrailLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BarTrailActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            lockScreenView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    leadingExpandedView(context: context)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    trailingExpandedView(context: context)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    bottomExpandedView(context: context)
                }
            } compactLeading: {
                // Compact Leading (left side of Dynamic Island)
                Image(systemName: "figure.walk")
                    .foregroundColor(.blue)
            } compactTrailing: {
                // Compact Trailing (right side of Dynamic Island)
                Text(formatDuration(context.state.elapsedTime))
                    .font(.caption2)
                    .foregroundColor(.white)
            } minimal: {
                // Minimal (when multiple activities)
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
            }
        }
    }
    
    // MARK: - Lock Screen View
    
    @ViewBuilder
    func lockScreenView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.yellow)
                Text("BarTrail Night in Progress")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(formatDuration(context.state.elapsedTime), systemImage: "clock.fill")
                        .font(.subheadline)
                    Text("Duration")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Label(formatDistance(context.state.currentDistance), systemImage: "figure.walk")
                        .font(.subheadline)
                    Text("Distance")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .frame(height: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(context.state.currentStops)", systemImage: "mappin.circle.fill")
                        .font(.subheadline)
                    Text("Stops")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
    }
    
    // MARK: - Dynamic Island Expanded Views
    
    @ViewBuilder
    func leadingExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "moon.stars.fill")
                .foregroundColor(.yellow)
                .font(.title2)
            Text("Night Out")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    func trailingExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(formatDuration(context.state.elapsedTime))
                .font(.title3.bold())
                .foregroundColor(.white)
            Text("elapsed")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    func bottomExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .foregroundColor(.blue)
                Text(formatDistance(context.state.currentDistance))
                    .font(.caption.bold())
                Text("Distance")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            VStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.purple)
                Text("\(context.state.currentStops)")
                    .font(.caption.bold())
                Text("Stops")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Helper Methods
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func formatDistance(_ distance: Double) -> String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}
