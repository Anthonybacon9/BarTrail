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
            lastSeenAt.timeIntervalSince(firstSeenAt)
        }
    }
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Location Manager Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        
        // Battery-optimized accuracy
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 25 // Update every 25 meters moved
        
        // Background tracking - only enable if background mode is configured
        #if !targetEnvironment(simulator)
        // Check if background modes are available
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        }
        #endif
        
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // Activity type for better power management
        locationManager.activityType = .fitness
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
            finalizeDwellIfQualified(candidate)
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
        // Filter out inaccurate locations
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 else {
            print("⚠️ Location filtered: poor accuracy (\(location.horizontalAccuracy)m)")
            return false
        }
        
        // Filter out stale locations (older than 60 seconds)
        guard location.timestamp.timeIntervalSinceNow > -60 else {
            print("⚠️ Location filtered: stale timestamp")
            return false
        }
        
        // Filter out invalid coordinates
        guard CLLocationCoordinate2DIsValid(location.coordinate) else {
            print("⚠️ Location filtered: invalid coordinates")
            return false
        }
        
        return true
    }
    
    // MARK: - Dwell Detection Logic
    
    private func processDwellDetection(for location: CLLocation) {
        guard let session = currentSession else { return }
        
        // Skip if location is moving fast (optional: filter out vehicle travel)
        if location.speed > 1.4 { // ~5 km/h walking speed threshold
            // User is moving, finalize any existing dwell
            if let candidate = dwellCandidate {
                finalizeDwellIfQualified(candidate)
                dwellCandidate = nil
                print("🚶 Moving detected - candidate cleared")
            }
            return
        }
        
        // Case 1: No current candidate - start tracking this location
        if dwellCandidate == nil {
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: Date(), // Use current time, not location timestamp
                lastSeenAt: Date()
            )
            print("🎯 New dwell candidate started at \(Date())")
            return
        }
        
        // Case 2: Check if still within radius of candidate
        guard var candidate = dwellCandidate else { return }
        let distance = location.distance(from: candidate.startLocation)
        
        if distance <= dwellRadiusMeters {
            // Still within radius - update lastSeenAt to NOW
            candidate.lastSeenAt = Date()
            candidate.locationCount += 1
            dwellCandidate = candidate
            
            let duration = candidate.duration
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("📍 Still at location (\(candidate.locationCount) updates, \(minutes)m \(seconds)s, \(String(format: "%.0f", distance))m from center)")
            
            // Check if we've met the duration threshold
            if duration >= dwellDurationSeconds {
                // This is a valid dwell!
                let dwellPoint = DwellPoint(
                    location: candidate.startLocation.coordinate,
                    startTime: candidate.firstSeenAt,
                    endTime: candidate.lastSeenAt
                )
                session.addDwell(dwellPoint)
                
                print("✅ DWELL DETECTED!")
                print("   Location: (\(dwellPoint.location.latitude), \(dwellPoint.location.longitude))")
                print("   Duration: \(formatDuration(dwellPoint.duration))")
                print("   Updates: \(candidate.locationCount)")
                
                // Optional: Send notification about dwell detection
                NotificationManager.shared.sendDwellDetectedNotification(
                    dwell: dwellPoint,
                    dwellNumber: session.dwells.count
                )
                
                // Clear candidate - we've logged this dwell
                dwellCandidate = nil
            }
        } else {
            // User left the area
            print("🚶 Left candidate area (moved \(String(format: "%.0f", distance))m)")
            
            // Check if the candidate qualified before they left
            finalizeDwellIfQualified(candidate)
            
            // Start new candidate at current location
            dwellCandidate = DwellCandidate(
                startLocation: location,
                firstSeenAt: Date(),
                lastSeenAt: Date()
            )
            print("🎯 New dwell candidate started at new location")
        }
    }
    
    private func finalizeDwellIfQualified(_ candidate: DwellCandidate) {
        guard let session = currentSession else { return }
        
        // Update lastSeenAt to now before checking
        var finalCandidate = candidate
        finalCandidate.lastSeenAt = Date()
        
        // Check if candidate met duration threshold
        if finalCandidate.duration >= dwellDurationSeconds {
            let dwellPoint = DwellPoint(
                location: finalCandidate.startLocation.coordinate,
                startTime: finalCandidate.firstSeenAt,
                endTime: finalCandidate.lastSeenAt
            )
            session.addDwell(dwellPoint)
            
            print("✅ DWELL FINALIZED (on departure)")
            print("   Duration: \(formatDuration(dwellPoint.duration))")
        } else {
            let duration = finalCandidate.duration
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            print("⏱️ Candidate didn't qualify (\(minutes)m \(seconds)s < \(Int(dwellDurationSeconds / 60))min)")
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
        
        // Process each location update
        for location in locations {
            // Validate location quality
            guard isLocationValid(location) else { continue }
            
            // Add to route
            session.addLocation(location)
            
            // Process dwell detection
            processDwellDetection(for: location)
            
            // Log for debugging
            let accuracy = String(format: "%.1f", location.horizontalAccuracy)
            let speed = location.speed >= 0 ? String(format: "%.1f", location.speed) : "N/A"
            print("📍 Location: (\(location.coordinate.latitude), \(location.coordinate.longitude)) | Accuracy: \(accuracy)m | Speed: \(speed)m/s")
        }
        
        // Trigger UI update
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
