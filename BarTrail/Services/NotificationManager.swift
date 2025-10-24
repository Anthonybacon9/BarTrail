//
//  NotificationManager.swift
//  BarTrail
//
//  Created by Anthony Bacon on 23/10/2025.
//


import Foundation
import UserNotifications
import CoreLocation
import Combine

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    let notificationCenter = UNUserNotificationCenter.current()
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                if let error = error {
                    print("❌ Notification authorization error: \(error.localizedDescription)")
                } else if granted {
                    print("✅ Notification authorization granted")
                } else {
                    print("⚠️ Notification authorization denied")
                }
            }
        }
    }
    
    func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // MARK: - Night End Notification
    
    func sendNightEndedNotification(session: NightSession) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Night Complete! 🎉"
        
        // Build summary
        let duration = session.duration ?? 0
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let distance = session.totalDistance
        let stops = session.dwells.count
        
        var body = ""
        if hours > 0 {
            body += "\(hours)h \(minutes)m"
        } else {
            body += "\(minutes) minutes"
        }
        
        if distance >= 1000 {
            body += " • \(String(format: "%.1f", distance / 1000))km"
        } else {
            body += " • \(Int(distance))m"
        }
        
        if stops > 0 {
            body += " • \(stops) stop\(stops == 1 ? "" : "s")"
        }
        
        content.body = body
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "NIGHT_ENDED"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "night_ended_\(session.id)", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error.localizedDescription)")
            } else {
                print("✅ Night ended notification scheduled")
            }
        }
    }
    
    // MARK: - Dwell Notification (Optional - during tracking)
    
    func sendDwellDetectedNotification(dwell: DwellPoint, dwellNumber: Int) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Stop #\(dwellNumber) Detected 📍"
        
        let duration = dwell.duration
        let minutes = Int(duration) / 60
        content.body = "You spent \(minutes) minutes at this location"
        
        content.sound = .default
        content.categoryIdentifier = "DWELL_DETECTED"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "dwell_\(dwell.id)", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule dwell notification: \(error.localizedDescription)")
            } else {
                print("✅ Dwell notification scheduled")
            }
        }
    }
    
    // MARK: - Long Night Warning (Optional)
    
    func scheduleLongNightWarning(hours: Int = 6) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Still Tracking? ⏰"
        content.body = "You've been tracking for \(hours) hours. Don't forget to stop when you're done!"
        content.sound = .default
        content.categoryIdentifier = "LONG_NIGHT"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: false)
        let request = UNNotificationRequest(identifier: "long_night_warning", content: content, trigger: trigger)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("❌ Failed to schedule long night warning: \(error.localizedDescription)")
            } else {
                print("✅ Long night warning scheduled for \(hours) hours")
            }
        }
    }
    
    func cancelLongNightWarning() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["long_night_warning"])
        print("🔕 Long night warning cancelled")
    }
    
    // MARK: - Clear Notifications
    
    func clearAllNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.removeAllPendingNotificationRequests()
        
        // Reset badge
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        print("📱 User tapped notification: \(identifier)")
        
        // You can handle different actions here
        // For example, open the map view when tapping night ended notification
        
        completionHandler()
    }
}
