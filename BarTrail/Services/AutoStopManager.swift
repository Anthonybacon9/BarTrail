//
//  AutoStopManager.swift
//  BarTrail
//
//  Created by Anthony Bacon on 24/10/2025.
//


import Foundation
import Combine
import UserNotifications

class AutoStopManager: ObservableObject {
    static let shared = AutoStopManager()
    
    @Published var isAutoStopEnabled = true
    @Published var autoStopHours: Int = 8 // Default 8 hours
    
    private var autoStopTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load settings
        loadSettings()
    }
    
    // MARK: - Auto Stop Control
    
    func startAutoStopTimer() {
        guard isAutoStopEnabled else { return }
        
        // Cancel any existing timer
        cancelAutoStopTimer()
        
        let interval = TimeInterval(autoStopHours * 3600)
        
        print("⏰ Auto-stop timer started: will stop after \(autoStopHours) hours")
        
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.triggerAutoStop()
        }
    }
    
    func cancelAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        print("⏰ Auto-stop timer cancelled")
    }
    
    private func triggerAutoStop() {
        guard SessionManager.shared.isTracking else { return }
        
        print("⏰ Auto-stop triggered after \(autoStopHours) hours")
        
        // Stop the session
        SessionManager.shared.stopNight()
        
        // Send notification
        NotificationManager.shared.sendAutoStopNotification(hours: autoStopHours)
    }
    
    // MARK: - Settings
    
    func saveSettings() {
        UserDefaults.standard.set(isAutoStopEnabled, forKey: "auto_stop_enabled")
        UserDefaults.standard.set(autoStopHours, forKey: "auto_stop_hours")
    }
    
    private func loadSettings() {
        if UserDefaults.standard.object(forKey: "auto_stop_enabled") != nil {
            isAutoStopEnabled = UserDefaults.standard.bool(forKey: "auto_stop_enabled")
        }
        
        if UserDefaults.standard.object(forKey: "auto_stop_hours") != nil {
            autoStopHours = UserDefaults.standard.integer(forKey: "auto_stop_hours")
        }
    }
}

// MARK: - Notification Extension

extension NotificationManager {
    func sendAutoStopNotification(hours: Int) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Night Auto-Stopped 🛑"
        content.body = "Your tracking session was automatically stopped after \(hours) hours for battery saving."
        content.sound = .default
        content.badge = 1
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "auto_stop_\(UUID())", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to send auto-stop notification: \(error)")
            } else {
                print("✅ Auto-stop notification sent")
            }
        }
    }
}
