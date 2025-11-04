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
            // Lock Screen / Banner UI (Strava style)
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.2))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded UI (Strava style)
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
                // Show clock until drinks are registered, then show glass
                Image(systemName: context.state.currentDrinks > 0 ? "wineglass.fill" : "clock.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            } compactTrailing: {
                // Show timer until drinks are registered, then show drink count
                if context.state.currentDrinks > 0 {
                    Text("\(context.state.currentDrinks)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Text(formatDurationCompact(context.state.elapsedTime))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            } minimal: {
                // Minimal - Just icon
                Image(systemName: "location.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }.supplementalActivityFamilies([])
    }
    
    // MARK: - Lock Screen View (Strava Style)
    
    @ViewBuilder
    func lockScreenView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "moon.stars.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14))
                }
                
                Text("Night Out")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Live indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
            }
            
            // Stats Grid (Strava style - clean and minimal)
            HStack(spacing: 0) {
                statColumn(
                    value: formatDuration(context.state.elapsedTime),
                    label: "Duration",
                    icon: "clock.fill",
                    color: Color(red: 0.4, green: 0.2, blue: 0.8)
                )
                
                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(height: 40)
                
                statColumn(
                    value: formatDistance(context.state.currentDistance),
                    label: "Distance",
                    icon: "figure.walk",
                    color: Color.blue
                )
//                
//                Divider()
//                    .background(Color.white.opacity(0.3))
//                    .frame(height: 40)
                
//                statColumn(
//                    value: "\(context.state.currentStops)",
//                    label: "Stops",
//                    icon: "mappin.circle.fill",
//                    color: Color.purple
//                )
                
                if context.state.currentDrinks > 0 {
                    Divider()
                        .background(Color.white.opacity(0.3))
                        .frame(height: 40)
                    
                    statColumn(
                        value: "\(context.state.currentDrinks)",
                        label: "Drinks",
                        icon: "🍺",
                        color: Color.orange,
                        isEmoji: true
                    )
                }
            }
        }
        .padding(16)
    }
    
    @ViewBuilder
    func statColumn(value: String, label: String, icon: String, color: Color, isEmoji: Bool = false) -> some View {
        VStack(spacing: 6) {
            if isEmoji {
                Text(icon)
                    .font(.system(size: 18))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Dynamic Island Expanded Views (Strava Style)
    
    @ViewBuilder
    func leadingExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.2, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
            }
            
            Text("Night Out")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    @ViewBuilder
    func trailingExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(formatDuration(context.state.elapsedTime))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
            }
        }
    }
    
    @ViewBuilder
    func bottomExpandedView(context: ActivityViewContext<BarTrailActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            // Distance
            expandedStat(
                icon: "figure.walk",
                value: formatDistance(context.state.currentDistance),
                label: "Distance",
                color: .blue
            )
            
//            // Stops
//            expandedStat(
//                icon: "mappin.circle.fill",
//                value: "\(context.state.currentStops)",
//                label: "Stops",
//                color: .purple
//            )
            
            // Drinks (if any)
            if context.state.currentDrinks > 0 {
                expandedStatEmoji(
                    emoji: "🍺",
                    value: "\(context.state.currentDrinks)",
                    label: "Drinks"
                )
            }
        }
        .padding(.horizontal, 8)
    }
    
    @ViewBuilder
    func expandedStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    func expandedStatEmoji(emoji: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 16))
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helper Methods
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    func formatDurationCompact(_ duration: TimeInterval) -> String {
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
