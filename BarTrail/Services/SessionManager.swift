import Foundation
import CoreLocation
import Combine

class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()
    
    @Published var currentSession: NightSession?
    @Published var isTracking = false
    
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // Live Activity update timer
    private var liveActivityUpdateTimer: Timer?
    
    // MARK: - Dwell Detection State
    private var dwellCandidate: DwellCandidate?
    private let dwellRadiusMeters: CLLocationDistance = 25
    private let dwellDurationSeconds: TimeInterval = 20 * 60 // 20 minutes
    
    private struct DwellCandidate {
        let startLocation: CLLocation
        let firstSeenAt: Date
        var lastSeenAt: Date
        var locationCount: Int = 1
        
        var duration: TimeInterval {
            return lastSeenAt.timeIntervalSince(firstSeenAt)
        }
    }
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        
        // Adaptive accuracy - better balance of accuracy vs battery
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters // Improved from HundredMeters
        locationManager.distanceFilter = 15 // Reduced from 25 meters for better precision
        
        // Better activity type for nightlife scenarios
        locationManager.activityType = .otherNavigation
        
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
            locationManager.pausesLocationUpdatesAutomatically = false
        }
        #endif
        
        // Request temporary full accuracy when needed
        if #available(iOS 14.0, *) {
            locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NightlifeTracking") { error in
                if let error = error {
                    print("⚠️ Full accuracy denied: \(error)")
                } else {
                    print("✅ Full accuracy granted for precise venue tracking")
                    // Temporarily increase accuracy when full accuracy is available
                    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
                    // Return to balanced accuracy after 2 hours
                    DispatchQueue.main.asyncAfter(deadline: .now() + 7200) {
                        self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                    }
                }
            }
        }
    }
    
    // MARK: - Session Control
    func startNight() {
        // Check authorization
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestAlwaysAuthorization()
            return
        }
        
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            print("⚠️ Location authorization denied")
            return
        }
        
        // Create new session
        currentSession = NightSession()
        isTracking = true
        
        // Start continuous location tracking
        locationManager.startUpdatingLocation()
        
        // Optional: Start visit monitoring for Apple's optimized detection
        locationManager.startMonitoringVisits()
        
        // Schedule long night warning (6 hours)
        NotificationManager.shared.scheduleLongNightWarning(hours: 6)
        
        // Start auto-stop timer if enabled
        AutoStopManager.shared.startAutoStopTimer()
        
        // Start Live Activity
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.startActivity(
                sessionId: currentSession!.id.uuidString,
                startTime: currentSession!.startTime
            )
            
            // Start timer to update Live Activity every 30 seconds
            startLiveActivityUpdateTimer()
        }
        
        print("✅ Night started at \(Date())")
        print("📍 Tracking with accuracy: \(locationManager.desiredAccuracy)m")
        print("📊 Distance filter: \(locationManager.distanceFilter)m")
    }
    
    func stopNight() {
        guard let session = currentSession else { return }
        
        // Check if there's a pending dwell candidate
        if let candidate = dwellCandidate {
            finalizeDwellIfQualified(candidate, currentTime: Date())
        }
        
        // Stop all tracking
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringVisits()
        
        // Mark session as ended
        session.end()
        isTracking = false
        
        // Clear dwell state
        dwellCandidate = nil
        
        // Cancel long night warning
        NotificationManager.shared.cancelLongNightWarning()
        
        // Cancel auto-stop timer
        AutoStopManager.shared.cancelAutoStopTimer()
        
        // Stop Live Activity update timer
        stopLiveActivityUpdateTimer()
        
        // Calculate stats
        let totalDistance = calculateTotalDistance(for: session.route)
        let duration = session.duration ?? 0
        
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.endActivity(
                finalDistance: session.totalDistance,
                finalStops: session.dwells.count,
                finalDrinks: session.drinks.total, // NEW
                duration: duration
            )
        }
        
        // Save session to storage
        SessionStorage.shared.saveSession(session)
        
        // Send night ended notification
        NotificationManager.shared.sendNightEndedNotification(session: session)
        
        
        print("🛑 Night stopped at \(Date())")
        print("📍 Total locations tracked: \(session.route.count)")
        print("🏠 Total dwells detected: \(session.dwells.count)")
        print("📏 Total distance: \(String(format: "%.2f", totalDistance / 1000))km")
        print("⏱️ Duration: \(formatDuration(duration))")
    }
    
    // MARK: - Helper Methods
    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    private func calculateTotalDistance(for locations: [CLLocation]) -> CLLocationDistance {
        guard locations.count > 1 else { return 0 }
        
        var totalDistance: CLLocationDistance = 0
        for i in 1..<locations.count {
            totalDistance += locations[i].distance(from: locations[i-1])
        }
        return totalDistance
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func isLocationValid(_ location: CLLocation) -> Bool {
        // Filter out inaccurate locations (tighter bounds)
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 else {
            print("⚠️ Location filtered: poor accuracy (\(location.horizontalAccuracy)m)")
            return false
        }
        
        // Filter out stale locations
        guard location.timestamp.timeIntervalSinceNow > -30 else { // Reduced from 60 to 30 seconds
            print("⚠️ Location filtered: stale timestamp")
            return false
        }
        
        // Filter out invalid coordinates
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            print("⚠️ Location filtered: invalid coordinates")
            return false
        }
        
        // Filter out altitude inaccuracies (optional)
        if location.verticalAccuracy > 100 {
            print("⚠️ Location filtered: poor vertical accuracy")
            return false
        }
        
        return true
    }
    
    // MARK: - Dwell Detection Logic
    
    private func processDwellDetection(for location: CLLocation) {
        guard let session = currentSession else { return }
        
        // Use CURRENT time, not location timestamp for dwell detection
        let currentTime = Date()
        
        // Skip if location is moving fast
        if location.speed > 1.4 {
            if let candidate = dwellCandidate {
                finalizeDwellIfQualified(candidate, currentTime: currentTime)
                dwellCandidate = nil
            }
            return
        }
        
        if dwellCandidate == nil {
            // START new candidate with CURRENT time
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: currentTime,
                lastSeenAt: currentTime
            )
            print("🎯 New dwell candidate started at \(currentTime)")
            return
        }
        
        guard var candidate = dwellCandidate else { return }
        let distance = location.distance(from: candidate.startLocation)
        
        if distance <= dwellRadiusMeters {
            // UPDATE with CURRENT time
            candidate.lastSeenAt = currentTime
            candidate.locationCount += 1
            dwellCandidate = candidate
            
            let duration = candidate.duration
            if duration >= dwellDurationSeconds {
                // Create dwell with PROPER dates
                let dwellPoint = DwellPoint(
                    location: candidate.startLocation.coordinate,
                    startTime: candidate.firstSeenAt,
                    endTime: candidate.lastSeenAt  // This should be current time
                )
                session.addDwell(dwellPoint)
                
                print("✅ DWELL DETECTED! Duration: \(formatDuration(dwellPoint.duration))")
                
                // Clear candidate
                dwellCandidate = nil
            }
        } else {
            // User left the area - finalize with CURRENT time
            finalizeDwellIfQualified(candidate, currentTime: currentTime)
            
            // Start new candidate
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: currentTime,
                lastSeenAt: currentTime
            )
        }
    }

    
    private func finalizeDwellIfQualified(_ candidate: DwellCandidate, currentTime: Date) {
        guard let session = currentSession else { return }
        
        var finalCandidate = candidate
        finalCandidate.lastSeenAt = currentTime
        
        if finalCandidate.duration >= dwellDurationSeconds {
            let dwellPoint = DwellPoint(
                location: finalCandidate.startLocation.coordinate,
                startTime: finalCandidate.firstSeenAt,
                endTime: finalCandidate.lastSeenAt
            )
            session.addDwell(dwellPoint)
            print("✅ DWELL FINALIZED on departure")
        }
    }
    
    // MARK: - Live Activity Updates
    
    private func startLiveActivityUpdateTimer() {
        guard #available(iOS 16.2, *) else { return }
        
        liveActivityUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateLiveActivity()
        }
    }
    
    private func stopLiveActivityUpdateTimer() {
        liveActivityUpdateTimer?.invalidate()
        liveActivityUpdateTimer = nil
    }
    
    @available(iOS 16.2, *)
    private func updateLiveActivity() {
        guard let session = currentSession, isTracking else { return }
        
        let elapsed = Date().timeIntervalSince(session.startTime)
        
        LiveActivityManager.shared.updateActivity(
            distance: session.totalDistance,
            stops: session.dwells.count,
            drinks: session.drinks.total, // NEW
            elapsedTime: elapsed
        )
    }
}

// MARK: - CLLocationManagerDelegate
extension SessionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let session = currentSession, isTracking else { return }
        
        for location in locations {
            guard isLocationValid(location) else { continue }
            
            // Use the location's timestamp directly for the route
            session.addLocation(location)
            
            // But use current time for dwell detection
            processDwellDetection(for: location)
            
            print("📍 Location at \(location.timestamp): (\(location.coordinate.latitude), \(location.coordinate.longitude))")
        }
        
        objectWillChange.send()
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard let session = currentSession, isTracking else { return }
        
        // Apple's visit detection provides an alternative to our manual dwell detection
        // We can use this as a backup or validation
        let arrivalDate = visit.arrivalDate
        let departureDate = visit.departureDate
        let duration = departureDate.timeIntervalSince(arrivalDate)
        
        print("🏠 Apple Visit detected:")
        print("   Location: (\(visit.coordinate.latitude), \(visit.coordinate.longitude))")
        print("   Arrival: \(arrivalDate)")
        print("   Departure: \(departureDate)")
        print("   Duration: \(formatDuration(duration))")
        print("   Accuracy: ±\(visit.horizontalAccuracy)m")
        
        // Optional: Use Apple's visit as a fallback dwell detection
        // Only if it meets our duration threshold and we don't have overlapping manual dwells
        if duration >= dwellDurationSeconds {
            // Check if we already detected this dwell manually
            let hasOverlap = session.dwells.contains { dwell in
                let dwellLocation = CLLocation(latitude: dwell.location.latitude, longitude: dwell.location.longitude)
                let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
                let distance = dwellLocation.distance(from: visitLocation)
                
                // Check if dwell overlaps in time and space
                return distance < 50 && // Within 50m
                       dwell.startTime < departureDate &&
                       dwell.endTime > arrivalDate
            }
            
            if !hasOverlap {
                let dwellPoint = DwellPoint(
                    location: visit.coordinate,
                    startTime: arrivalDate,
                    endTime: departureDate
                )
                session.addDwell(dwellPoint)
                print("✅ Apple Visit added as dwell (no manual overlap)")
            } else {
                print("ℹ️ Apple Visit overlaps with manual dwell - skipped")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📱 Location authorization changed: \(status.rawValue)")
        
        switch status {
        case .notDetermined:
            print("   Status: Not determined")
        case .authorizedAlways:
            print("   Status: Always authorized ✓")
        case .authorizedWhenInUse:
            print("   Status: When in use (⚠️ background tracking limited)")
        case .denied:
            print("   Status: Denied")
        case .restricted:
            print("   Status: Restricted")
        @unknown default:
            print("   Status: Unknown")
        }
        
        // If user just granted permission and we're trying to track, start
        if isTracking && (status == .authorizedAlways || status == .authorizedWhenInUse) {
            locationManager.startUpdatingLocation()
            locationManager.startMonitoringVisits()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        // Handle specific error cases
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("   Error: Location access denied by user")
                isTracking = false
            case .network:
                print("   Error: Network-related location error")
            default:
                print("   Error code: \(clError.code.rawValue)")
            }
        }
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("⏸️ Location updates paused by system")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("▶️ Location updates resumed")
    }
}
